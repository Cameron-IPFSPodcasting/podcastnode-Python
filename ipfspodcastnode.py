#!/usr/bin/env python3
import sys
import subprocess
import json
import requests
import shutil
import time
import random
import logging
import os

if len(sys.argv) > 1:
  #Get email from command line
  email = sys.argv[1]
else:
  #Enter your email for support & management via IPFSPodcasting.net/Manage
  email = 'email@example.com'

#Basic logging to ipfspodcastnode.log
logging.basicConfig(format="%(asctime)s : %(message)s", datefmt="%Y-%m-%d %H:%M:%S", filename="ipfspodcastnode.log", level=logging.INFO)

#Find ipfs, wget, wc
ipfspath = shutil.which('ipfs', 0, '/usr/local/bin:/usr/bin:/bin:' + os.environ['HOME'] + '/bin' )
if ipfspath == None:
  logging.error("ipfs-cli executable not found")
  sys.exit(100)

wgetpath = shutil.which('wget')
if wgetpath == None:
  logging.error("wget executable not found")
  sys.exit(101)

wcpath = shutil.which('wc')
if wcpath == None:
  logging.error("wc executable not found")
  sys.exit(102)


#Randomize requests so not all in the same second
wait=random.randint(1,150)
logging.info('Sleeping ' + str(wait) + ' seconds...')
time.sleep(wait)

payload = { 'email': email, 'version': '0.6p' }

#Get IPFS ID
ipid = subprocess.run(ipfspath + ' id', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if ipid.returncode == 0:
  ipfs = json.loads(ipid.stdout)
  payload['ipfs_id'] = ipfs['ID']

#Check if IPFS is running, and restart if necessary.
diag = subprocess.run(ipfspath + ' diag sys', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if diag.returncode == 0:
  ipfs = json.loads(diag.stdout)
  payload['ipfs_ver'] = ipfs['ipfs_version']
  payload['online'] = ipfs['net']['online']
  if payload['online'] == False:
    #Start the IPFS daemon
    daemon = subprocess.run(ipfspath + ' daemon >/dev/null 2>&1 &', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    logging.info('@@@ IPFS NOT RUNNING !!! Restarting Daemon @@@')

#Get Peer Count
peercnt = 0
speers = subprocess.run(ipfspath + ' swarm peers|' + wcpath + ' -l', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
if speers.returncode == 0:
  peercnt = speers.stdout.decode().strip()
payload['peers'] = peercnt

#Request work
logging.info('Requesting work...')
try:
  response = requests.post("https://IPFSPodcasting.net/Request", timeout=120, data=payload)
  work = json.loads(response.text)
  logging.info('Response : ' + str(work))
except requests.RequestException as e:
  logging.info('Error during request : ' + str(e))
  work = { 'message': 'Request Error' }

if work['message'] == 'Request Error':
  logging.info('Error requesting work from IPFSPodcasting.net (check internet / firewall / router).')

elif work['message'][0:7] != 'No Work':
  if work['download'] != '' and work['filename'] != '':
    logging.info('Downloading ' + str(work['download']))

    #Download any "downloads" and Add to IPFS (1hr48min timeout)
    try:
      hash = subprocess.run(wgetpath + ' -q --no-check-certificate "' + work['download'] + '" -O - | ' + ipfspath + ' add -q -w --stdin-name "' + work['filename'] + '"', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6500)
      hashcode = hash.returncode
    except subprocess.SubprocessError as e:
      logging.info('Error downloading/pinning episode : ' + str(e))
      #Clean up any other wget/add commands that may have spawned
      cleanup = subprocess.run('kill `ps aux|grep -E \'(ipfs ad[d]|no-check-certificat[e])\'|awk \'{ print $2 }\'`', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      hashcode = 99

    if hashcode == 0:
      #Get file size (for validation)
      downhash=hash.stdout.decode().strip().split('\n')
      size = subprocess.run(ipfspath + ' cat ' + downhash[0] + ' | ' + wcpath + ' -c', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      downsize=size.stdout.decode().strip()
      logging.info('Added to IPFS ( hash : ' + str(downhash[0]) + ' length : ' + str(downsize) + ')')
      payload['downloaded'] = downhash[0] + '/' + downhash[1]
      payload['length'] = downsize
    else:
      payload['error'] = hashcode

  if work['pin'] != '':
    #Directly pin if already in IPFS
    logging.info('Pinning hash (' + str(work['pin']) + ')')
    try:
      pin = subprocess.run(ipfspath + ' pin add ' + work['pin'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=6500)
      pincode = pin.returncode
    except subprocess.SubprocessError as e:
      logging.info('Error direct pinning : ' + str(e))
      #Clean up any other pin commands that may have spawned
      cleanup = subprocess.run('kill `ps aux|grep "ipfs pin ad[d]"|awk \'{ print $2 }\'`', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      pincode = 98

    if pincode == 0:
      #Verify Success and return full CID & Length
      pinchk = subprocess.run(ipfspath + ' ls ' + work['pin'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
      if pinchk.returncode == 0:
        hashlen=pinchk.stdout.decode().strip().split(' ')
        payload['pinned'] = hashlen[0] + '/' + work['pin']
        payload['length'] = hashlen[1]
      else:
        payload['error'] = pinchk.returncode
    else:
      payload['error'] = pincode

  if work['delete'] != '':
    #Delete/unpin any expired episodes
    logging.info('Unpinned old/expired hash (' + str(work['delete']) + ')')
    delete = subprocess.run(ipfspath + ' pin rm ' + work['delete'], shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    payload['deleted'] = work['delete']

  #Report Results
  logging.info('Reporting results...')
  #Get Usage/Available
  repostat = subprocess.run(ipfspath + ' repo stat -s|grep RepoSize', shell=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
  if repostat.returncode == 0:
    repolen = repostat.stdout.decode().strip().split(':')
    used = int(repolen[1].strip())
  else:
    used = 0
  payload['used'] = used
  df = os.statvfs('/')
  payload['avail'] = df.f_bavail * df.f_frsize
  #logging.info('Results : ' + str(payload))
  try:
    response = requests.post("https://IPFSPodcasting.net/Response", timeout=120, data=payload)
  except requests.RequestException as e:
    logging.info('Error sending response : ' + str(e))

else:
  logging.info('No work.')
