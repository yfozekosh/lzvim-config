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
  dotnet-sdk-9.0 \
  neovim \
  && dnf clean all

RUN dnf install -y nodejs

# Set up user
RUN useradd -ms /bin/bash yfozekosh 
USER yfozekosh 
WORKDIR /home/yfozekosh

# Install your Neovim config
RUN git clone https://github.com/yfozekosh/lzvim-config ~/.config/nvim

# Install tmux plugin manager
RUN git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# Add tmux configuration using a heredoc
# Add tmux configuration (line-by-line echo, safe for Docker)
RUN echo "set -g @plugin 'tmux-plugins/tpm'" >> /home/yfozekosh/.tmux.conf && \
  echo "set -g @plugin 'tmux-plugins/tmux-sensible'" >> /home/yfozekosh/.tmux.conf && \
  echo "set -g @plugin 'alexwforsythe/tmux-which-key'" >> /home/yfozekosh/.tmux.conf && \
  echo "" >> /home/yfozekosh/.tmux.conf && \
#  echo "unbind C-b" >> /home/yfozekosh/.tmux.conf && \
#  echo "set -g prefix C-Space" >> /home/yfozekosh/.tmux.conf && \
#  echo "bind C-Space send-prefix" >> /home/yfozekosh/.tmux.conf && \
  echo "set -g base-index 1" >> /home/yfozekosh/.tmux.conf && \
  echo "" >> /home/yfozekosh/.tmux.conf && \
  echo "set -g default-terminal \"tmux-256color\"" >> /home/yfozekosh/.tmux.conf && \
  echo "set -ga terminal-overrides \",xterm-256color:Tc\"" >> /home/yfozekosh/.tmux.conf && \
  echo "" >> /home/yfozekosh/.tmux.conf && \
  echo "run '~/.tmux/plugins/tpm/tpm'" >> /home/yfozekosh/.tmux.conf

# Install Samsung netcoredbg (specific release)
RUN curl -LO https://github.com/Samsung/netcoredbg/releases/download/3.1.2-1054/netcoredbg-linux-amd64.tar.gz \
  && tar -xzf netcoredbg-linux-amd64.tar.gz \
  && mv netcoredbg ~/dotnetcoredbg \
  && rm netcoredbg-linux-amd64.tar.gz

# Add netcoredbg to PATH
ENV PATH="/home/yfozekosh/netcoredbg:$PATH"

RUN echo "export TERM=xterm-256color" >> /home/yfozekosh/.bashrc && \
    echo "export COLORTERM=truecolor" >> /home/yfozekosh/.bashrc

# Neovim config
RUN nvim --headless "+Lazy! install" +qa

# On container start, open tmux
CMD ["/bin/bash"]
