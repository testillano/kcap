# Kubernetes captures image

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://codedocs.xyz/testillano/kcap.svg)](https://codedocs.xyz/testillano/kcap/index.html)
[![Ask Me Anything !](https://img.shields.io/badge/Ask%20me-anything-1abc9c.svg)](https://github.com/testillano)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/testillano/kcap/graphs/commit-activity)
[![Build docker image and publish to Docker Hub](https://github.com/testillano/kcap/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/testillano/kcap/actions/workflows/docker-publish.yml)

This project hosts the stuff to build the `kcap` docker image useful to capture traffic within a kubernetes cluster.

## Project image

This image is already available at `docker hub` for every repository `tag`, and also for master as `latest`:

```bash
docker pull testillano/kcap:<tag>
```

You could also build it using the script `./build.sh` located at project root.

In case that your *SUT* has restricted access to *docker hub*, you could mirror the former `kcap` image in another docker registry location, and then export it on `KCAP_IMG` environment variable to override the default image used by the scripts described below:

## Usage

You may use the following scripts to complete 4 different actions in a natural order (`capture -> retrieve -> [unpatch] -> [merge]`). Invoke them with `-h|--help` to get more detail:

`./capture.sh`

* Patch deployments/statefulsets within provided namespace to include a `kcap` container at every pod.
* Start captures by mean kubectl remote execution of `/kcap/start.sh` within every `kcap` container (it uses `tshark`).

`./retrieve.sh`

* Retrieve all the artifacts to ease further analysis.

`./unpatch.sh`

* Optionally, unpatch affected deployments.

`./merge.sh`

* Optionally, you may merge all the gathered `pcap` files available within the artifacts structure retrieved using an auxiliary `kcap` image container through `/kcap/merge.sh` image utility. This is focused in building sequence diagrams for HTTP/2 traffic, so the list of HTTP/2 ports should be provided to improve the procedure results (this is done automatically anyway).

## Download

The project scripts can be used separately without need to clone/download this project because deployment patching procedure will pull the `kcap` docker image from Docker Hub when needed. Just copy/paste the following in a `bash` shell, and run `./capture.sh` script to start:

```bash
wget https://raw.githubusercontent.com/testillano/kcap/master/\
{capture.sh,retrieve.sh,unpatch.sh,merge.sh} && \
chmod +x {capture.sh,retrieve.sh,unpatch.sh,merge.sh}
```

## Demo

There is a demo chart which deploys two [HTTP2 Agents](https://github.com/testillano/h2agent) with two replicas each, then starts captures and generate traffic using their component test image. Finally, stops captures and retrieves artifacts:

```bash
./demo.sh
```

## License

This project is licensed under the [MIT License](http://opensource.org/licenses/MIT) and also uses the opensource project [5G Visualizer](https://github.com/telekom/5g-trace-visualizer/blob/master/LICENSE) from Deutsche Telekom.

