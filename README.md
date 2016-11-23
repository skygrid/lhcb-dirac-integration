# lhcb-dirac-integration

To run LHCb DIRAC jobs on Skygrid you wouldn eed:

1. Modified version of VAC/VCycle [script](https://github.com/skygrid/lhcb-dirac-integration/blob/master/skygrid_execution_script.sh)
2. [cern/slc6-base](https://hub.docker.com/r/cern/slc6-base/) docker image
3. LHCb host certificate which DN is configured in DIRAC system

Job submission script would look like this:
```python
from libscheduler import Metascheduler
ms = Metascheduler("http://metascheduler")

queue = ms.queue('docker_queue')


job_description = {
    "descriptor": {
        "name" : "LHCb job",
        "env_container" : {
            "workdir" : "",
            "name" : "cern/slc6-base:latest",
            "entrypoint": "/bin/sh /input/skygrid_execution_script.sh",
            "volumes": ["/cvmfs:/cvmfs"]
        },
        "output_uri" : "dcache:/lhcb/output/$JOB_ID",
        "cmd": "",
        "args" : {
        },
        "cpu_per_container" : 1,
        "max_memoryMB" : 1024,
        "min_memoryMB" : 512
    },
    "input": [
        "dcache:/lhcb/input/lhcbhost.pem",
        "dcache:/lhcb/input/skygrid_execution_script.sh",
    ]
}


job = queue.put(job_description)

print job.job_id 
print job.status
```
