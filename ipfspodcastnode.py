#!/usr/bin/env python3
import sys
import subprocess
import json
import requests
import shutil
import argparse
import time
import random
import logging
import os
from typing import TYPE_CHECKING, Optional

if TYPE_CHECKING:
    from _types import RequestPayload, WorkRequest, ResponsePayload

argument_parser = argparse.ArgumentParser(description="IPFS Podcast Node")
argument_parser.add_argument(
    "email",
    type=str,
    help="Your email for support & management via IPFSPodcasting.net/Manage",
)
argument_parser.add_argument(
    "--turbo-mode",
    dest="turbo_mode",
    action="store_true",
    help="Runs until a failure occurs or there's no more work.",
)
parsed_arguments = argument_parser.parse_args()
email = parsed_arguments.email
turbo_mode_enabled = parsed_arguments.turbo_mode

# Basic logging to ipfspodcastnode.log
logging.basicConfig(
    format="%(asctime)s : %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
    filename="ipfspodcastnode.log",
    level=logging.INFO,
)

# Find ipfs & wc
ipfspath = shutil.which(
    "ipfs",
    0,
    "/usr/local/bin:/usr/bin:/bin:" + os.environ["HOME"] + "/bin",
)
if ipfspath is None:
    logging.error("ipfs executable not found")
    sys.exit(100)

wcpath = shutil.which("wc")
if wcpath is None:
    logging.error("wc executable not found")
    sys.exit(102)

_ipfs_id: Optional[str] = None


def generate_default_payload() -> "RequestPayload":
    payload: "RequestPayload" = {"email": email, "version": "0.7p"}

    # Get IPFS ID
    global _ipfs_id
    if _ipfs_id is None:
        ipid = subprocess.run(
            ipfspath + " id", shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        if ipid.returncode == 0:
            _ipfs_id = json.loads(ipid.stdout).get("ID")

    if _ipfs_id is not None:
        payload["ipfs_id"] = _ipfs_id

    # Check if IPFS is running, and restart if necessary.
    diag = subprocess.run(
        ipfspath + " diag sys",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if diag.returncode == 0:
        ipfs = json.loads(diag.stdout)
        payload["ipfs_ver"] = ipfs["ipfs_version"]
        payload["online"] = ipfs["net"]["online"]
        if payload["online"] is False:
            # Start the IPFS daemon
            subprocess.run(
                ipfspath + " daemon >/dev/null 2>&1 &",
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            logging.warning("@@@ IPFS NOT RUNNING !!! Restarting Daemon @@@")
    else:
        payload["online"] = False

    # Get Peer Count
    peercnt = 0
    speers = subprocess.run(
        ipfspath + " swarm peers|" + wcpath + " -l",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if speers.returncode == 0:
        peercnt = int(speers.stdout.decode().strip())
    payload["peers"] = peercnt

    return payload


payload = generate_default_payload()


def request_work(payload: "RequestPayload") -> Optional["WorkRequest"]:
    # Request work
    logging.info("Requesting work...")
    try:
        response = requests.post(
            "https://IPFSPodcasting.net/Request", timeout=120, data=payload
        )
        work: WorkRequest = json.loads(response.text)
        logging.info("Response : " + str(work))
    except requests.RequestException as e:
        logging.error("Error during request : " + str(e))
        logging.error(
            "Error requesting work from IPFSPodcasting.net (check internet / firewall / router)."
        )
        return None

    if work["message"].startswith("No Work"):
        logging.info("No work.")
        return None

    return work


def process_work(
    request_payload: "RequestPayload", work: "WorkRequest"
) -> "ResponsePayload":
    payload: "ResponsePayload" = request_payload

    if work["download"] != "" and work["filename"] != "":
        logging.info(f"Downloading {work['download']}")
        # Download any "downloads" and Add to IPFS (1hr48min timeout)
        try:
            response = requests.get(work["download"], stream=True, timeout=6500)
            if response.ok:
                hash = subprocess.Popen(
                    (ipfspath, "add", "-q", "-w", "--stdin-name", work["filename"]),
                    stdin=subprocess.PIPE,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )
                downsize = 0
                for chunk in response.iter_content(
                    256 * 1024
                ):  # download in 256kB chunks
                    downsize += len(chunk)
                    hash.stdin.write(chunk)
                hash.stdin.close()
                hashcode = hash.wait(timeout=6500)
                if downsize == 0:
                    logging.error("Empty download")
                    hashcode = 97
            else:
                logging.error(f"Download error : {response.status_code}")
                hashcode = 97
        except subprocess.SubprocessError as e:
            logging.info("Error downloading/pinning episode : " + str(e))
            # Clean up any other "ipfs add" commands that may have spawned
            subprocess.run(
                "kill `ps aux|grep -E '(ipfs ad[d]|no-check-certificat[e])'|awk '{ print $2 }'`",
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            hashcode = 99

        if hashcode == 0:
            # Get file size (for validation)
            downhash = hash.stdout.read().decode().strip().split("\n")
            logging.info(f"Added to IPFS ( hash : {downhash[0]}  length : {downsize})")
            payload["downloaded"] = downhash[0] + "/" + downhash[1]
            payload["length"] = downsize
        else:
            payload["error"] = hashcode

    if work["pin"] != "":
        # Directly pin if already in IPFS
        logging.info(f"Pinning hash ({work['pin']})")
        try:
            pin = subprocess.run(
                ipfspath + " pin add " + work["pin"],
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=6500,
            )
            pincode = pin.returncode
        except subprocess.SubprocessError as e:
            logging.info("Error direct pinning : " + str(e))
            # Clean up any other pin commands that may have spawned
            subprocess.run(
                "kill `ps aux|grep \"ipfs pin ad[d]\"|awk '{ print $2 }'`",
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            pincode = 98

        if pincode == 0:
            # Verify Success and return full CID & Length
            pinchk = subprocess.run(
                ipfspath + " ls " + work["pin"],
                shell=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
            )
            if pinchk.returncode == 0:
                hashlen = pinchk.stdout.decode().strip().split(" ")
                payload["pinned"] = hashlen[0] + "/" + work["pin"]
                payload["length"] = hashlen[1]
            else:
                payload["error"] = pinchk.returncode
        else:
            payload["error"] = pincode

    if work["delete"] != "":
        # Delete/unpin any expired episodes
        logging.info(f"Unpinned old/expired hash ({work['delete']})")
        subprocess.run(
            ipfspath + " pin rm " + work["delete"],
            shell=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        payload["deleted"] = work["delete"]
    return payload


def report_result(payload: "ResponsePayload"):
    # Report Results
    logging.info("Reporting results...")
    # Get Usage/Available
    repostat = subprocess.run(
        ipfspath + " repo stat -s|grep RepoSize",
        shell=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if repostat.returncode == 0:
        repolen = repostat.stdout.decode().strip().split(":")
        used = int(repolen[1].strip())
    else:
        used = 0
    payload["used"] = used
    ipfs_data_path = os.environ.get("IPFS_PATH", os.environ.get("HOME", "/"))
    df = os.statvfs(ipfs_data_path)
    payload["avail"] = df.f_bavail * df.f_frsize
    # logging.info('Results : ' + str(payload))
    try:
        response = requests.post(
            "https://IPFSPodcasting.net/Response", timeout=120, data=payload
        )
        responsedata = json.loads(response.text)
    except requests.RequestException as e:
        logging.info("Error sending response : " + str(e))
        responsedata = {"status": "Error"}

    logging.info("Response data : " + str(responsedata))
    return responsedata["status"]


if __name__ == "__main__":
    # Randomize requests so not all in the same second
    wait = random.randint(1, 150)
    logging.info("Sleeping " + str(wait) + " seconds...")
    time.sleep(wait)
    if turbo_mode_enabled:
        logging.info("Turbo mode enabled, running in loop...")

    while True:
        payload = generate_default_payload()
        work = request_work(payload)
        if work is None:
            break
        payload = process_work(payload, work)
        status = report_result(payload)
        if not turbo_mode_enabled or status != "Success":
            break
        logging.info("Continuing in turbo mode...")
