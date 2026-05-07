# syntax=docker/dockerfile:1.6
FROM nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

SHELL ["/bin/bash", "-c"]

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    RCUTILS_COLORIZED_OUTPUT=1 \
    CMAKE_BUILD_TYPE=RelWithDebInfo \
    ROS_DISTRO=humble \
    DEBIAN_FRONTEND=noninteractive

# Install locales and other necessary tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
      locales software-properties-common \
      curl gnupg2 lsb-release ca-certificates \
    && locale-gen en_US.UTF-8 \
    && update-locale LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8

RUN add-apt-repository universe \
    && apt-get update \
    && apt-get install -y --no-install-recommends curl python3 ca-certificates \
    && ROS_APT_SOURCE_VERSION="$(curl -fsSL -H 'User-Agent: docker' -H 'Accept: application/vnd.github+json' \
      https://api.github.com/repos/ros-infrastructure/ros-apt-source/releases/latest \
      | python3 -c 'import sys,json; print(json.load(sys.stdin)["tag_name"])')" \
    && test -n "${ROS_APT_SOURCE_VERSION}" \
    && CODENAME="$(. /etc/os-release && echo ${UBUNTU_CODENAME:-${VERSION_CODENAME}})" \
    && curl -fsSL -o /tmp/ros2-apt-source.deb \
      "https://github.com/ros-infrastructure/ros-apt-source/releases/download/${ROS_APT_SOURCE_VERSION}/ros2-apt-source_${ROS_APT_SOURCE_VERSION}.${CODENAME}_all.deb" \
    && dpkg -i /tmp/ros2-apt-source.deb \
    && rm -f /tmp/ros2-apt-source.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
      ros-${ROS_DISTRO}-desktop \
      ros-dev-tools \
      python3-rosdep python3-colcon-common-extensions python3-vcstool \
    && rosdep init \
    && rosdep update

# -----------------------------------------------------------------------------
# System deps + pip deps (with constraints to prevent numpy 2.x)
# -----------------------------------------------------------------------------
RUN --mount=type=cache,sharing=locked,target=/var/cache/apt \
    --mount=type=cache,sharing=locked,target=/var/lib/apt \
    --mount=type=cache,sharing=locked,target=/root/.cache \
    set -euxo pipefail \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        bash-completion build-essential cmake gdb git htop nano iputils-ping net-tools sudo wget vim v4l-utils \
        clang-format ccache liburdfdom-tools usbutils \
        libxcb1 libx11-6 libxext6 libxrender1 libxkbcommon0 libxfixes3 libxi6 libxrandr2 libxcursor1 libxcomposite1 libxdamage1 \
        libglib2.0-0 libgl1 libsm6 libgtk-3-0 \
        libnvinfer-bin \
        gfortran liblapack-dev libblas-dev libopenblas-dev coinor-libipopt-dev swig pkg-config libmetis-dev libgmp-dev \
        python3 python3-venv python3-distutils python3-dev python-is-python3 python3-flake8 python3-pip python3-setuptools ipython3 \
        \
        # deps eigenpy/hppfcl/pinocchio (source build)
        libeigen3-dev libboost-all-dev libboost-python-dev \
        liburdfdom-dev libconsole-bridge-dev libtinyxml2-dev \
        pybind11-dev \
        libassimp-dev liboctomap-dev libqhull-dev \
    && rm -rf /var/lib/apt/lists/* \
    \
    # ---- pip constraints: force numpy<2 everywhere ----
    && python -m pip install -U pip \
    && printf "numpy==1.26.4\n" > /tmp/constraints.txt \
    \
    # install numpy first (pinned by constraints)
    && python -m pip install -c /tmp/constraints.txt "numpy==1.26.4" \
    \
    # torch stack
    && python -m pip install -c /tmp/constraints.txt \
        --extra-index-url https://download.pytorch.org/whl/cu121 \
        "torch==2.4.1+cu121" "torchvision==0.19.1+cu121" "torchaudio==2.4.1+cu121" \
    \
    # the rest (also constrained)
    && python -m pip install -c /tmp/constraints.txt --upgrade-strategy only-if-needed \
        argcomplete pre-commit \
        quadprog pyrealsense2 ultralytics opencv-python meshcat \
        onnxruntime-gpu onnx \
        looseversion keyboard xacrodoc pynput \
    && python -m pip check \
    \
    # sanity: make sure numpy is <2 right now
    && python -c "import numpy as np; assert int(np.__version__.split('.')[0]) < 2, np.__version__; print('numpy ok:', np.__version__, np.__file__)"

# -----------------------------------------------------------------------------
# Backlog of the image
# -----------------------------------------------------------------------------
RUN mkdir -p /opt/manifest; \
  python -m pip freeze > /opt/manifest/pip_freeze.txt; \
  dpkg-query -W > /opt/manifest/dpkg.txt; \
  apt-mark showmanual > /opt/manifest/apt_manual.txt

# -----------------------------------------------------------------------------
# Workspace layout
# -----------------------------------------------------------------------------
RUN mkdir -p /root/workspace/deps /root/workspace/ros_ws
WORKDIR /root/workspace
RUN echo "source /opt/ros/${ROS_DISTRO}/setup.bash" >> /root/.bashrc

# -----------------------------------------------------------------------------
# Build BLASFEO, FATROP, CasADi from source (installed into /usr/local)
# -----------------------------------------------------------------------------
WORKDIR /root/workspace/deps

RUN git clone https://github.com/giaf/blasfeo.git; \
    cd blasfeo; \
    git checkout 9923ac8a63d710d894a3d2987d885002df69db74; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DTARGET=X64_AUTOMATIC \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

RUN git clone https://github.com/meco-group/fatrop.git; \
    cd fatrop; \
    git checkout 45ee388750ba2b4cf7ba603203d4c12431e485fe; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTS=OFF; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

RUN git clone https://github.com/casadi/casadi.git; \
    cd casadi; \
    git checkout 3.7.2; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DWITH_IPOPT=ON -DWITH_BUILD_IPOPT=ON \
      -DWITH_FATROP=ON \
      -DWITH_OPENMP=ON -DWITH_THREAD=ON \
      -DWITH_BUILD_MUMPS=ON -DWITH_BUILD_METIS=ON \
      -DWITH_PYTHON=ON -DWITH_PYTHON3=ON \
      -DPYTHON_PREFIX="$(python -c 'from distutils.sysconfig import get_python_lib; print(get_python_lib())')" \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release; \
    make -j1 mumps-external; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

# -----------------------------------------------------------------------------
# Build eigenpy from source (pinned) -> installs /usr/local/lib{,64}/cmake/eigenpy + libeigenpy.so
# -----------------------------------------------------------------------------
RUN git clone https://github.com/stack-of-tasks/eigenpy.git; \
    cd eigenpy; \
    git checkout v3.12.0; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DPython_EXECUTABLE=/usr/bin/python \
      -DCMAKE_PREFIX_PATH="/usr/local"; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

# -----------------------------------------------------------------------------
# Build Pinocchio from source WITH CasADi + Python bindings + HPP-FCL (pinned) + example_robot_data for cosmik
# -----------------------------------------------------------------------------
RUN git clone https://github.com/coal-library/coal.git; \
    cd coal; \
    git checkout v3.0.2; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DBUILD_PYTHON_INTERFACE=ON \
      -DCOAL_BACKWARD_COMPATIBILITY_WITH_HPP_FCL=ON \
      -DPYTHON_EXECUTABLE=/usr/bin/python \
      -DPython_EXECUTABLE=/usr/bin/python \
      -Deigenpy_DIR=/usr/local/lib/cmake/eigenpy \
      -DCMAKE_PREFIX_PATH="/usr/local"; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

RUN git clone --recursive https://github.com/stack-of-tasks/pinocchio.git; \
    cd pinocchio; \
    git checkout v3.9.0; \
    git submodule update --init --recursive; \
    mkdir -p build; \
    cd build; \
    cmake .. \
      -DCMAKE_INSTALL_PREFIX=/usr/local \
      -DCMAKE_BUILD_TYPE=Release \
      -DBUILD_TESTING=OFF \
      -DBUILD_EXAMPLES=OFF \
      -DBUILD_BENCHMARK=OFF \
      -DBUILD_PYTHON_INTERFACE=ON \
      -DBUILD_WITH_CASADI_SUPPORT=ON \
      -DBUILD_WITH_COLLISION_SUPPORT=ON \
      -DPython_EXECUTABLE=/usr/bin/python \
      -Deigenpy_DIR=/usr/local/lib/cmake/eigenpy \
      -DCMAKE_PREFIX_PATH="/usr/local"; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

RUN git clone --recursive https://github.com/Gepetto/example-robot-data.git; \
    cd example-robot-data; \
    git checkout fd8f0286c471af75fcff549cea83e9fbc11a0578; \
    git submodule update --init --recursive; \
    mkdir -p build; \
    cd build; \
    cmake ..; \
    make -j"$(nproc-5)"; \
    make install; \
    ldconfig

WORKDIR /root/workspace

RUN git clone https://github.com/MaximeSabbah/nlf_test.git /root/workspace/nlf_test

RUN git clone --branch nlf_humble --depth 1 https://github.com/mathiste1706/RT-COSMIK.git root/workspace/RT-COSMIK


# Env helpers (minimal; Python already sees /usr/local site-packages by default)
RUN echo "export PYTHONPATH=$PYTHONPATH:/usr/local/lib/python3.10/site-packages" >> /root/.bashrc && \
    echo "export LD_LIBRARY_PATH=/usr/local/lib:\$LD_LIBRARY_PATH" >> /root/.bashrc && \
    echo "export LIBRARY_PATH=/usr/local/lib:\$LIBRARY_PATH" >> /root/.bashrc && \
    echo "export CPATH=/usr/local/include:\$CPATH" >> /root/.bashrc && \
    echo "export PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:\$PKG_CONFIG_PATH" >> /root/.bashrc
    
RUN bash RT-COSMICK/scripts//bash/fetch_models.sh
CMD ["bash"]
