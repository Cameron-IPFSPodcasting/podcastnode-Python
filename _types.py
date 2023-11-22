from typing import Literal
from typing_extensions import TypedDict, NotRequired


class RequestPayload(TypedDict):
    email: str  # user email
    version: str  # version of the current package
    online: bool  #
    ipfs_id: NotRequired[str]  # ipfs id
    ipfs_ver: NotRequired[str]  # ipfs version
    peers: int  # number of peers


class WorkRequest(TypedDict):
    message: str
    # related to downloading
    download: str
    filename: str
    # related to pinning
    pin: str

    # related to deleting
    delete: str


class ResponsePayload(RequestPayload):
    error: NotRequired[int]  # error code to report back to the server
    # size of the downloaded file (in bytes) or the number of items pinned
    length: NotRequired[int]
    used: int  # number of bytes used by ipfs on disk
    avail: int  # number of bytes available to the ipfs disk
    # related to downloading
    downloaded: NotRequired[str]  # status of download
    # related to pinning
    pinned: NotRequired[str]  # status of pinning
    # related to deleting
    deleted: NotRequired[str]


class ResponseStatus(TypedDict):
    status: Literal["Success", "Fail", "Error"]
