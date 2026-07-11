FROM node:22

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG PHP_VERSION=8.4

# Install basic development tools, iptables/ipset, and PHP 8.4
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  zsh \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  curl \
  ca-certificates \
  sqlite3 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Add sury.org PHP repository for PHP 8.4 on Debian Bookworm
RUN curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \
  && echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ bookworm main" \
     > /etc/apt/sources.list.d/php.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
     php${PHP_VERSION}-cli \
     php${PHP_VERSION}-curl \
     php${PHP_VERSION}-mbstring \
     php${PHP_VERSION}-xml \
     php${PHP_VERSION}-zip \
     php${PHP_VERSION}-bcmath \
     php${PHP_VERSION}-intl \
     php${PHP_VERSION}-readline \
     php${PHP_VERSION}-sqlite3 \
     php${PHP_VERSION}-pgsql \
     php${PHP_VERSION}-mysql \
     php${PHP_VERSION}-gd \
     php${PHP_VERSION}-redis \
     php${PHP_VERSION}-pcov \
     php${PHP_VERSION}-imagick \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sLS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Set DEVCONTAINER environment variable
ENV DEVCONTAINER=true

# Create workspace directory
# Note: .claude is now a bind mount from the host, not created here
RUN mkdir -p /workspace && \
  chown -R node:node /workspace

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Set up non-root user
USER node

# Install global npm packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default shell to zsh
ENV SHELL=/bin/zsh

# Set the default editor
ENV EDITOR=nano
ENV VISUAL=nano

RUN curl -fsSL https://claude.ai/install.sh | bash

# Global gitignore: exclude .claude/ directories from all workspace repos
RUN echo '.claude/' > /home/node/.gitignore_global && \
    git config --global core.excludesfile /home/node/.gitignore_global

USER root
RUN ln -sf /home/node/.local/bin/claude /usr/local/bin/claude

USER node

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh, /sbin/iptables, /usr/sbin/iptables, /usr/sbin/sysctl" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall
USER node
