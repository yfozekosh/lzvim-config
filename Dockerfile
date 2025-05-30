FROM fedora:latest

# Install basic dependencies
RUN dnf install -y \
  git \
  curl \
  unzip \
  tar \
  libicu \
  krb5-libs \
  zlib \
  glibc-langpack-en \
  tmux \
  gcc \
  make \
  cmake \
  wget \
  openssl \
  dotnet-sdk-8.0 \
  && dnf clean all

# Download and install the latest Neovim (Linux x64 AppImage)
RUN curl -LO https://github.com/neovim/neovim/releases/latest/download/nvim.appimage \
  && chmod u+x nvim.appimage \
  && ./nvim.appimage --appimage-extract \
  && mv squashfs-root /opt/nvim \
  && ln -s /opt/nvim/AppRun /usr/local/bin/nvim

# Set up user
RUN useradd -ms /bin/bash devuser
USER devuser
WORKDIR /home/devuser

# Install your Neovim config
RUN git clone https://github.com/yfozekosh/lzvim-config ~/.config/nvim

# Install tmux plugin manager
RUN git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# tmux.conf setup
RUN echo "\
  set -g @plugin 'tmux-plugins/tpm'\n\
  set -g @plugin 'tmux-plugins/tmux-sensible'\n\
  set -g @plugin 'alexwforsythe/tmux-which-key'\n\
  run '~/.tmux/plugins/tpm/tpm'\n\
  unbind C-b\n\
  set-option -g prefix C-Space\n\
  bind C-Space send-prefix\n\
  set -g base-index 1\n" > ~/.tmux.conf

# Install Samsung's vsdbg (debugger)
RUN mkdir -p ~/vsdbg && curl -sSL https://aka.ms/getvsdbgsh | bash /dev/stdin -v latest -l ~/vsdbg

# On container start, open tmux
CMD ["tmux"]
