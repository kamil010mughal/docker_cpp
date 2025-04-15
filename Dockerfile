
# --------------------------
# BASE STAGE
# --------------------------
FROM ubuntu:22.04 AS base

ARG C_COMPILER=gcc
ARG CXX_COMPILER=g++
ARG COMPILER_VERSION=10
ARG BUILD_TYPE=Release

# Install dependencies
RUN apt-get update -qq && export DEBIAN_FRONTEND=noninteractive && \
    apt-get install -y --no-install-recommends \
    make cmake ninja-build \
    python3.10 python3-pip \
    ${C_COMPILER}-${COMPILER_VERSION} \
    ${CXX_COMPILER}-${COMPILER_VERSION}

# Set environment variables for compilers
ENV CC=${C_COMPILER}-${COMPILER_VERSION}
ENV CXX=${CXX_COMPILER}-${COMPILER_VERSION}

# Install Conan v2+ and configure
RUN python3 -m pip install --upgrade pip setuptools && \
    python3 -m pip install "conan>=2.0.0" && \
    conan profile detect --force && \
    conan config set general.default_profile=default && \
    conan profile set settings.compiler=${C_COMPILER} && \
    conan profile set settings.compiler.version=${COMPILER_VERSION} && \
    conan profile set settings.compiler.libcxx=libstdc++11

ENV CONAN_SYSREQUIRES_SUDO=0
ENV CONAN_SYSREQUIRES_MODE=enabled

# Set working directory
WORKDIR /docker_cpp

# Copy Conan configuration
COPY conanfile.txt conanfile.txt

# Install Conan dependencies
RUN conan install . \
    --install-folder=build/${BUILD_TYPE}/modules \
    --settings=build_type=${BUILD_TYPE} \
    --build=missing

# Copy source code
COPY . .

# --------------------------
# TEST STAGE
# --------------------------
FROM base AS test

ARG BUILD_TYPE=Release

RUN cmake -G Ninja \
    -D CMAKE_BUILD_TYPE=${BUILD_TYPE} \
    -D UNIT_TESTS=ON \
    -B ./build/${BUILD_TYPE} \
    -S . && \
    cmake --build ./build/${BUILD_TYPE} --config ${BUILD_TYPE} && \
    ctest --test-dir ./build/${BUILD_TYPE} \
    --config ${BUILD_TYPE} \
    --output-junit results.xml \
    --output-on-failure -j$(nproc)

# --------------------------
# BUILD STAGE
# --------------------------
FROM base AS build

ARG BUILD_TYPE=Release

RUN cmake -G Ninja \
    -D CMAKE_BUILD_TYPE=${BUILD_TYPE} \
    -D UNIT_TESTS=OFF \
    -B ./build/${BUILD_TYPE} \
    -S . && \
    cmake --build ./build/${BUILD_TYPE} --config ${BUILD_TYPE} && \
    cmake --install ./build/${BUILD_TYPE} --prefix ./install

# --------------------------
# FINAL IMAGE
# --------------------------
FROM ubuntu:22.04 AS publish

# Copy built files from build stage
COPY --from=build /docker_cpp/install /docker_cpp

# Default command to run the app
CMD ["./docker_cpp/app"]
