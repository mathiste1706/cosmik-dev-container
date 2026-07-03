# syntax=docker/dockerfile:1.6
FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

SHELL ["/bin/bash", "-c"]

# Grouped all ENV variables together
ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    RCUTILS_COLORIZED_OUTPUT=1 \
    CMAKE_BUILD_TYPE=RelWithDebInfo \
    DEBIAN_FRONTEND=noninteractive \
    PIP_BREAK_SYSTEM_PACKAGES=1 \
    PYTHONPATH=/usr/local/lib/python3.12/dist-packages:/usr/local/lib/python3.12/site-packages:/usr/local/lib/python3/dist-packages:/usr/local/lib/python3/site-packages:/usr/local/lib64/python3.12/dist-packages:/usr/local/lib64/python3.12/site-packages:${PYTHONPATH} \
    LD_LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:${LD_LIBRARY_PATH} \
    LIBRARY_PATH=/usr/local/lib:/usr/local/lib64:${LIBRARY_PATH} \
    CPATH=/usr/local/include:${CPATH} \
    PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:/usr/local/lib64/pkgconfig:${PKG_CONFIG_PATH}

# 1. Install System Dependencies (Combined)
RUN apt-get update && apt-get install -y --no-install-recommends \
      locales software-properties-common curl gnupg2 lsb-release ca-certificates \
    && locale-gen en_US.UTF-8 && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    && add-apt-repository universe \
    && apt-get update && apt-get install -y --no-install-recommends \
        bash-completion build-essential cmake gdb git htop nano iputils-ping net-tools sudo wget vim v4l-utils \
        clang-format ccache liburdfdom-tools usbutils \
        libxcb1 libx11-6 libxext6 libxrender1 libxkbcommon0 libxfixes3 libxi6 libxrandr2 libxcursor1 libxcomposite1 libxdamage1 \
        libglib2.0-0 libgl1 libsm6 libgtk-3-0 libnvinfer-bin \
        gfortran liblapack-dev libblas-dev libopenblas-dev coinor-libipopt-dev swig pkg-config libmetis-dev libgmp-dev \
        python3 python3-venv python3-dev python-is-python3 python3-flake8 python3-pip python3-setuptools ipython3 \
        libeigen3-dev libboost-all-dev libboost-python-dev liburdfdom-dev libconsole-bridge-dev libtinyxml2-dev pybind11-dev \
        libassimp-dev liboctomap-dev libqhull-dev ffmpeg\
    && rm -rf /var/lib/apt/lists/*

# 2. Python & Pip Dependencies
RUN --mount=type=cache,sharing=locked,target=/root/.cache \
    set -euxo pipefail \
    && printf "numpy==1.26.4\n" > /tmp/constraints.txt \
    && python -m pip install -c /tmp/constraints.txt "numpy==1.26.4" \
    && python -m pip install -c /tmp/constraints.txt --extra-index-url https://download.pytorch.org/whl/cu121 \
        "torch==2.4.1+cu121" "torchvision==0.19.1+cu121" "torchaudio==2.4.1+cu121" \
    && python -m pip install -c /tmp/constraints.txt --upgrade-strategy only-if-needed \
        argcomplete pre-commit quadprog pyrealsense2 ultralytics opencv-python meshcat \
        onnxruntime-gpu onnx looseversion keyboard xacrodoc pynput \
    && python -m pip check || true

# 3. THE SQUASHED BUILD LAYER (Builds everything, then deletes the waste)
RUN mkdir -p /root/workspace/deps && cd /root/workspace/deps \
    \
    && echo "Building blasfeo..." \
    && git clone https://github.com/giaf/blasfeo.git && cd blasfeo && git checkout 9923ac8a63d710d894a3d2987d885002df69db74 \
    && mkdir build && cd build && cmake .. -DTARGET=X64_AUTOMATIC -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building fatrop..." \
    && git clone https://github.com/meco-group/fatrop.git && cd fatrop && git checkout 45ee388750ba2b4cf7ba603203d4c12431e485fe \
    && mkdir build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTS=OFF && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building casadi..." \
    && git clone https://github.com/casadi/casadi.git && cd casadi && git checkout 3.7.2 \
    && mkdir build && cd build && cmake .. -DWITH_IPOPT=ON -DWITH_BUILD_IPOPT=ON -DWITH_FATROP=ON -DWITH_OPENMP=ON -DWITH_THREAD=ON -DWITH_BUILD_MUMPS=ON -DWITH_BUILD_METIS=ON -DWITH_PYTHON=ON -DWITH_PYTHON3=ON -DPYTHON_PREFIX="$(python -c 'import sysconfig; print(sysconfig.get_path("platlib"))')" -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release \
    && make -j1 mumps-external && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building eigenpy..." \
    && git clone --recursive https://github.com/stack-of-tasks/eigenpy.git && cd eigenpy && git checkout v3.12.0 && git submodule update --init --recursive \
    && mkdir build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DPython_EXECUTABLE=/usr/bin/python3 -DCMAKE_PREFIX_PATH="/usr/local" && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building coal..." \
    && git clone --recursive https://github.com/coal-library/coal.git && cd coal && git checkout v3.0.2 && git submodule update --init --recursive \
    && mkdir build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DBUILD_PYTHON_INTERFACE=ON -DCOAL_BACKWARD_COMPATIBILITY_WITH_HPP_FCL=ON -DPython_EXECUTABLE=/usr/bin/python3 -DCMAKE_PREFIX_PATH="/usr/local" && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building pinocchio..." \
    && git clone --recursive https://github.com/stack-of-tasks/pinocchio.git && cd pinocchio && git checkout v3.9.0 && git submodule update --init --recursive \
    && mkdir build && cd build && cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local -DCMAKE_BUILD_TYPE=Release -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DBUILD_BENCHMARK=OFF -DBUILD_PYTHON_INTERFACE=ON -DBUILD_WITH_CASADI_SUPPORT=ON -DBUILD_WITH_COLLISION_SUPPORT=ON -DPython_EXECUTABLE=/usr/bin/python3 -DCMAKE_PREFIX_PATH="/usr/local" && make -j"$(nproc)" && make install && cd ../.. \
    \
    && echo "Building example-robot-data..." \
    && git clone --recursive https://github.com/Gepetto/example-robot-data.git && cd example-robot-data && git checkout fd8f0286c471af75fcff549cea83e9fbc11a0578 && git submodule update --init --recursive \
    && mkdir build && cd build && cmake .. && make -j"$(nproc)" && make install && cd ../.. \
    \
    && ldconfig \
    && echo "Cleaning up build dependencies to save disk space..." \
    && rm -rf /root/workspace/deps

# 4. Workspace setup & Backlog
WORKDIR /root/workspace

RUN git clone https://github.com/MaximeSabbah/nlf_test.git /root/workspace/nlf_test \
    && git clone --branch nlf_humble --depth 1 https://github.com/mathiste1706/RT-COSMIK.git /root/workspace/RT-COSMIK

RUN mkdir -p /opt/manifest \
    && python -m pip freeze > /opt/manifest/pip_freeze.txt \
    && dpkg-query -W > /opt/manifest/dpkg.txt \
    && apt-mark showmanual > /opt/manifest/apt_manual.txt

CMD ["bash"]
