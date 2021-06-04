FROM ubuntu:20.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update -y && \
    apt-get install -y curl python3-pip git && \
    rm -rf /var/lib/apt/lists/*

# Install a YAML Linter
ARG yamllint_version=1.26.1
LABEL yamllint_version=$yamllint_version
RUN pip install "yamllint==$yamllint_version"

# Install Yamale YAML schema validator
ARG yamale_version=3.0.6
LABEL yamale_version=$yamale_version
RUN pip install "yamale==$yamale_version"

# Install kubectl (if you don't know please get help)
ARG kubectl_version=v1.21.1
LABEL kubectl_version=$kubectl_version
RUN curl -LO "https://storage.googleapis.com/kubernetes-release/release/$kubectl_version/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && \
    mv kubectl /usr/local/bin/

# Install Helm (https://helm.sh)
ARG helm_version=v3.5.4
LABEL helm_version=$helm_version
RUN curl -LO "https://get.helm.sh/helm-$helm_version-linux-amd64.tar.gz" && \
    mkdir -p "/usr/local/helm-$helm_version" && \
    tar -xzf "helm-$helm_version-linux-amd64.tar.gz" -C "/usr/local/helm-$helm_version" && \
    ln -s "/usr/local/helm-$helm_version/linux-amd64/helm" /usr/local/bin/helm && \
    rm -f "helm-$helm_version-linux-amd64.tar.gz"

# Install Chart testing (https://github.com/helm/chart-testing)
ARG ct_version=3.4.0
LABEL ct_version=$ct_version
RUN curl -LO "https://github.com/helm/chart-testing/releases/download/v${ct_version}/chart-testing_${ct_version}_linux_amd64.tar.gz" && \
    mkdir -p "/usr/local/ct-$ct_version" && \
    tar -xzf "chart-testing_${ct_version}_linux_amd64.tar.gz" -C "/usr/local/ct-$ct_version" && \
    ln -s "/usr/local/ct-$ct_version/ct" /usr/local/bin/ct && \
    rm -f "chart-testing_${ct_version}_linux_amd64.tar.gz"

# Install pack (https://buildpacks.io/)
ARG pack_version=v0.18.1
LABEL pack_version=$pack_version
RUN curl -LO "https://github.com/buildpacks/pack/releases/download/${pack_version}/pack-${pack_version}-linux.tgz" && \
    mkdir -p "/usr/local/pack-$pack_version" && \
    tar -xzf "pack-${pack_version}-linux.tgz" -C "/usr/local/pack-$pack_version" && \
    ln -s "/usr/local/pack-$pack_version/pack" /usr/local/bin/pack && \
    rm -f "pack-${pack_version}-linux.tgz"

ENTRYPOINT ["/usr/bin/bash"]