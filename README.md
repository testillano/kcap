# Kubernetes captures image (WORK-IN-PROGRESS)

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Documentation](https://codedocs.xyz/testillano/kcap.svg)](https://codedocs.xyz/testillano/kcap/index.html)
[![Ask Me Anything !](https://img.shields.io/badge/Ask%20me-anything-1abc9c.svg)](https://github.com/testillano)
[![Maintenance](https://img.shields.io/badge/Maintained%3F-yes-green.svg)](https://github.com/testillano/kcap/graphs/commit-activity)
[![Build docker image and publish to Docker Hub](https://github.com/testillano/kcap/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/testillano/kcap/actions/workflows/docker-publish.yml)

This project hosts the stuff to build the `kcap` docker image useful to capture traffic within a kubernetes cluster.

## Project image

This image is already available at `docker hub` for every repository `tag`, and also for master as `latest`:

```bash
$ docker pull testillano/kcap:<tag>
```

You could also build it using the script `./build.sh` located at project root.

## Usage

You may use a procedure like `./capture.sh` to perform the following actions:

* Patch deployments within provided namespace in order to start `kcap` image within every deployment pod.
* Start captures by mean kubectl remote execution of `/kcap/start.sh` within the `kcap` image.
* Retrieve all the artifacts to ease further analisys.
* Upload artifacts together to a single `kcap` container.
* Merge them by mean kubectl remote execution of `/kcap/merge.sh` within former container.
* Retrieve the final artifacts.
* Unpatch affected deployments.

## Download

The script `capture.sh` can be used separately without need to clone/download this project because deployment patching procedure will pull the `kcap` docker image from Docker Hub when needed:

```bash
$ wget https://raw.githubusercontent.com/testillano/kcap/master/capture.sh && chmod +x capture.sh
```

## License

This project is licensed under the [MIT License](http://opensource.org/licenses/MIT) and also uses the opensource project [5G Visualizer](https://github.com/telekom/5g-trace-visualizer/blob/master/LICENSE) from Deutsche Telekom.

