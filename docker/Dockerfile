FROM chocotechnologies/dmod:1.0.3

RUN apt-get update -qq && apt-get install -y \
        wget \
        libncurses5 \
        policykit-1 \
        libgtk2.0-0 \
        screen \
        uml-utilities \
        libc6-dev \
        gcc \
        python3 \
        python3-pip

# Install Renode
ENV RENODE_VERSION="1.15.3"
RUN wget -q https://github.com/renode/renode/releases/download/v${RENODE_VERSION}/renode_${RENODE_VERSION}_amd64.deb
RUN dpkg -i ./renode_${RENODE_VERSION}_amd64.deb || apt-get install -f -y
RUN rm ./renode_${RENODE_VERSION}_amd64.deb

# Install dmffs
RUN wget -q https://github.com/choco-technologies/dmffs/releases/download/v1.0/dmffs-v1.0-x86_64.zip
RUN unzip dmffs-v1.0-x86_64.zip -d /tmp/dmffs
RUN mv /tmp/dmffs/*.dmf ${DMOD_DMF_DIR}
RUN mv /tmp/dmffs/*.dmfc ${DMOD_DMFC_DIR}
RUN echo "alias make_dmffs='dmod_loader ${DMOD_DMF_DIR}/make_dmffs.dmf --args'" >> ~/.bashrc

