# Dockerfile for Hyperledger fabric all-in-one development, including:
# * fabric-peer
# * fabric-orderer
# * fabric-ca
# * cryptogen
# * configtxgen
# * chaintools
# * gotools

# If you need a pure peer node to run, please see the 
# * yeasy/hyperledger-peer
# * yeasy/hyperledger-orderer
# * yeasy/hyperledger-ca

# Workdir is set to $GOPATH/src/github.com/hyperledger/fabric
# Data is stored under /var/hyperledger/db and /var/hyperledger/production

FROM golang:1.8
LABEL maintainer "Baohua Yang <yangbaohua@gmail.com>"

# fabric-peers
EXPOSE 7050
EXPOSE 7051

# fabric-ca-server RESTful
EXPOSE 7054

ENV DEBIAN_FRONTEND noninteractive

# Only useful for this Dockerfile
ENV FABRIC_ROOT $GOPATH/src/github.com/hyperledger/fabric
ENV FABRIC_CA_ROOT $GOPATH/src/github.com/hyperledger/fabric-ca
ENV ARCH x86_64

# version for the base images, e.g., fabric-ccenv, fabric-baseos
ENV BASE_VERSION 0.3.0
# version for the peer/orderer binaries, the community version tracks the hash value like 1.0.0-snapshot-51b7e85
ENV PROJECT_VERSION 1.0.0-preview
# generic builder environment: builder: $(DOCKER_NS)/fabric-ccenv:$(ARCH)-$(PROJECT_VERSION)
ENV DOCKER_NS hyperledger
# for golang or car's baseos: $(BASE_DOCKER_NS)/fabric-baseos:$(ARCH)-$(BASE_VERSION)
ENV BASE_DOCKER_NS hyperledger
ENV LD_FLAGS="-X github.com/hyperledger/fabric/common/metadata.Version=${PROJECT_VERSION} \
             -X github.com/hyperledger/fabric/common/metadata.BaseVersion=${BASE_VERSION} \
             -X github.com/hyperledger/fabric/common/metadata.BaseDockerLabel=org.hyperledger.fabric \
             -X github.com/hyperledger/fabric/common/metadata.DockerNamespace=hyperledger \
             -X github.com/hyperledger/fabric/common/metadata.BaseDockerNamespace=hyperledger"

# peer env 
ENV FABRIC_CFG_PATH /etc/hyperledger/fabric
ENV CORE_PEER_MSPCONFIGPATH $FABRIC_CFG_PATH/msp
# ignore handshake, since not using mutual TLS
ENV CORE_PEER_GOSSIP_SKIPHANDSHAKE true
ENV CORE_LOGGING_LEVEL DEBUG

# orderer env 
ENV ORDERER_GENERAL_GENESISPROFILE=SampleInsecureSolo
ENV ORDERER_GENERAL_LOCALMSPDIR $FABRIC_CFG_PATH/msp
ENV ORDERER_GENERAL_LISTENADDRESS 0.0.0.0
ENV CONFIGTX_ORDERER_ORDERERTYPE=solo

# ca env, # ca-server and ca-client will check the following env in order, to get the home cfg path
ENV FABRIC_CA_HOME /etc/hyperledger/fabric-ca-server
ENV FABRIC_CA_SERVER_HOME /etc/hyperledger/fabric-ca-server
ENV FABRIC_CA_CLIENT_HOME $HOME/.fabric-ca-client
ENV CA_CFG_PATH /etc/hyperledger/fabric-ca

RUN mkdir -p /var/hyperledger/db \
        /var/hyperledger/production \
        $GOPATH/src/github.com/hyperledger \
        $FABRIC_CFG_PATH \
        /chaincode/input \
        /chaincode/output \
        $FABRIC_CA_SERVER_HOME \
        $FABRIC_CA_CLIENT_HOME \
        $CA_CFG_PATH \
        /var/hyperledger/fabric-ca-server

# Install development dependencies
RUN apt-get update \
        && apt-get install -y apt-utils python-dev \
        && apt-get install -y libsnappy-dev zlib1g-dev libbz2-dev libyaml-dev libltdl-dev libtool \
        && apt-get install -y python-pip \
        && apt-get install -y vim tree \
        && pip install --upgrade pip \
        && pip install behave nose docker-compose \
        && rm -rf /var/cache/apt

# Install chaintool
RUN curl -L https://github.com/hyperledger/fabric-chaintool/releases/download/v0.10.1/chaintool > /usr/local/bin/chaintool \
        && chmod a+x /usr/local/bin/chaintool

# Install gotools
RUN go get github.com/golang/lint/golint \
        && go get github.com/kardianos/govendor \
        && go get github.com/golang/protobuf/protoc-gen-go \
        && go get github.com/onsi/ginkgo/ginkgo \
        && go get github.com/axw/gocov/... \
        && go get github.com/AlekSi/gocov-xml \
        && go get golang.org/x/tools/cmd/goimports

# Clone the Hyperledger Fabric code and cp sample config files
RUN cd $GOPATH/src/github.com/hyperledger \
        && git clone --single-branch -b master --depth 1 http://gerrit.hyperledger.org/r/fabric \
        && cp $FABRIC_ROOT/devenv/limits.conf /etc/security/limits.conf \
        && cp -r $FABRIC_ROOT/sampleconfig/* $FABRIC_CFG_PATH/

# install configtxgen and cryptogen
RUN cd $FABRIC_ROOT/ \
        && CGO_CFLAGS=" " go install -tags "nopkcs11" -ldflags "$LD_FLAGS" github.com/hyperledger/fabric/common/configtx/tool/configtxgen \
        && CGO_CFLAGS=" " go install -tags "nopkcs11" -ldflags "$LD_FLAGS" github.com/hyperledger/fabric/common/tools/cryptogen

# install fabric peer
RUN cd $FABRIC_ROOT/peer \
        && CGO_CFLAGS=" " go install -ldflags "$LD_FLAGS -linkmode external -extldflags '-static -lpthread'" \
        && go clean

# install fabric orderer
RUN cd $FABRIC_ROOT/orderer \
        && CGO_CFLAGS=" " go install -ldflags "$LD_FLAGS -linkmode external -extldflags '-static -lpthread'" \
        && go clean

# install fabric-ca
RUN cd $GOPATH/src/github.com/hyperledger \
    && git clone --single-branch -b master --depth 1 https://github.com/hyperledger/fabric-ca \
# This will install fabric-ca-server and fabric-ca-client into $GOPATH/bin/
    && go install -ldflags " -linkmode external -extldflags '-static -lpthread'" github.com/hyperledger/fabric-ca/cmd/... \
# Copy example ca and key files
    && cp $FABRIC_CA_ROOT/images/fabric-ca/payload/*.pem $FABRIC_CA_HOME/ \
    && go clean

# This is useful to debug local code with mapping inside
VOLUME $GOPATH/src/github.com/hyperledger
# The data and config dir, can map external one with -v
VOLUME /var/hyperledger
VOLUME $FABRIC_CFG_PATH
VOLUME $FABRIC_CA_SERVER_HOME
VOLUME $FABRIC_CA_CLIENT_HOME

# Useful scripts for quickly compiling local code
ADD *.sh /tmp/

# This is only a workaround for current hard-coded problem when using as fabric-baseimage.
RUN ln -s $GOPATH /opt/gopath

WORKDIR $FABRIC_ROOT
