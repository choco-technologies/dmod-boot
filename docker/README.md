# Building the Ubuntu 24.04 images

The image tags are intentionally reused: `dmod:1.0.4` and `dmboot:1.0.0`.
Build the images in dependency order so that dmboot uses the updated dmod base.

From the **dmod** repository:

```sh
docker build -t chocotechnologies/dmod-env:latest -f Docker/Dockerfile.env .
docker build -t chocotechnologies/dmod:1.0.4 -f Docker/Dockerfile .
```

From the **dmod-boot** repository:

```sh
docker build -t chocotechnologies/dmboot-env:1.0.0 -f docker/Dockerfile.env .
docker build -t chocotechnologies/dmboot:1.0.0 \
    --build-arg ENV_IMAGE_VERSION=1.0.0 -f docker/Dockerfile .
```

Do not pull an older published base over the locally rebuilt image between
these steps. After publishing replacement images, consumers should pull the
same tags again to refresh their local copies.

Renode 1.15.3 uses the portable distribution, which includes its Mono runtime.
Its Debian package depends on GTK# 2 packages unavailable in Ubuntu 24.04.
Do not use `dpkg -i ... || apt-get install -f`: apt can remove Renode to repair
dependencies and still return success. The image build checks that both
`renode` and the `file` command used by CI actually run.

The emulation test waits for `DMBOOT_RENODE_READY` at the end of the generated
Renode script before connecting its GDB monitor. Portable Renode can take
longer than five seconds to initialize; a fixed startup sleep is insufficient.

Check the resulting image:

```sh
docker run --rm chocotechnologies/dmboot:1.0.0 sh -ec \
    'cat /etc/os-release; renode --version; file --version; arm-none-eabi-gcc --version'
```

Run the full emulation suite, including the required TAP network test, from a
clean checkout with initialized submodules:

```sh
docker run --rm --cap-add=NET_ADMIN --device=/dev/net/tun \
    -e DMBOOT_TEST_NETWORK=1 \
    -v "$PWD:/workspace" -w /workspace \
    chocotechnologies/dmboot:1.0.0 ./scripts/run_renode_tests.sh
```
