# Kubernetes captures image

This project hosts the stuff to build the `kcap` docker image useful to capture traffic within a kubernetes cluster.

## Project image

This image is already available at `docker hub` for every repository `tag`, and also for master as `latest`:

```bash
$ docker pull testillano/kcap:<tag>
```

You could also build it using the script `./build.sh` located at project root.

## Usage

Yo may use a procedure like `./capture.sh` to perform the following actions:

* Patch deployments within provided namespace in order to start `kcap` image within every deployment pod.
* Start captures by mean kubectl remote execution of `/kcap/start.sh` within the `kcap` image.
* Retrieve all the artifacts to ease further analisys.
* Upload artifacts together to a single `kcap` container.
* Merge them by mean kubectl remote execution of `/kcap/merge.sh` within former container.
* Retrieve the final artifacts.
* Unpatch affected deployments.

