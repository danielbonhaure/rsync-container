
########################
## CREATE FINAL IMAGE ##
########################

# Create image
FROM debian:bullseye-slim AS final_image

# set environment variables
ARG DEBIAN_FRONTEND=noninteractive

# Install OS packages
RUN apt-get -y -qq update && \
    apt-get -y -qq --no-install-recommends install \
        # to run rsync
        rsync \
        # to run ssh-keygen
        openssh-client \
        # to send public key to rsync destine
        sshpass \
        # install Tini (https://github.com/krallin/tini#using-tini)
        tini \
        # to see process with pid 1
        htop \
        # to run sudo
        sudo \
        # to allow edit files
        vim \
        # to run process with cron
        cron && \
    rm -rf /var/lib/apt/lists/*

# Setup cron to allow it run as a non root user
RUN sudo chmod u+s $(which cron)



#######################
## SETUP FINAL IMAGE ##
#######################

# Create image
FROM final_image

# Set passwords
ARG ROOT_PWD
ARG NON_ROOT_PWD

# Pasar a root
USER root

# Modify root password
RUN echo "root:$ROOT_PWD" | chpasswd

# Create a non-root user, so the container can run as non-root
# OBS: the UID and GID must be the same as the user that own the
# input and the output volumes, so there isn't perms problems!!
ARG NON_ROOT_USR="nonroot"
ARG NON_ROOT_UID="1000"
ARG NON_ROOT_GID="1000"
RUN groupadd --gid $NON_ROOT_GID $NON_ROOT_USR
RUN useradd --uid $NON_ROOT_UID --gid $NON_ROOT_GID --comment "Non-root User Account" --create-home $NON_ROOT_USR

# Modify the password of non-root user
RUN echo "$NON_ROOT_USR:$NON_ROOT_PWD" | chpasswd

# Add non-root user to sudoers
RUN adduser $NON_ROOT_USR sudo

# Conf passwordless ssh:
USER $NON_ROOT_USR
# Generar clave pública y privada
RUN mkdir -p /tmp/.ssh && \
    ssh-keygen -b 2048 -t rsa -f /tmp/.ssh/id_rsa -q -N ""
# Copiar clave al servidor detino de los pronos
ARG SSHUSER
ARG SSHPASS
ARG SSHHOST
RUN sshpass -e ssh-copy-id -i /tmp/.ssh/id_rsa -o StrictHostKeyChecking=no -f ${SSHUSER}@${SSHHOST}
# Al finalizar la configuración de ssh se vuelve al usuario root
USER root

# Setup cron
ARG RSYNC_CMD="rsync -e 'ssh -i /tmp/.ssh/id_rsa' -iPavhz --chown=nobody:nogroup"
ARG RDR_OUTPUT_CMD=">> /proc/1/fd/1 2>> /proc/1/fd/1"
ARG CRON_TIME_STR="0 0 20 * *"
ARG SRC_FILES="/data/{folder1/*.html,folder2/*.html}"
ARG DEST_FOLDER="/tmp"
RUN (echo "${CRON_TIME_STR} ${RSYNC_CMD} ${SRC_FILES} ${SSHUSER}@${SSHHOST}:${DEST_FOLDER} ${RDR_OUTPUT_CMD}") | \
    crontab -u $NON_ROOT_USR -

# Add Tini (https://github.com/krallin/tini#using-tini)
ENTRYPOINT ["/usr/bin/tini", "-g", "--"]

# Run your program under Tini (https://github.com/krallin/tini#using-tini)
CMD ["cron", "-f"]
# or docker run your-image /your/program ...

# Access non-root user directory
WORKDIR /home/$NON_ROOT_USR

# Switch back to non-root user to avoid accidental container runs as root
USER $NON_ROOT_USR



# CONSTRUIR CONTENEDOR
# export DOCKER_BUILDKIT=1
# docker build --file Dockerfile \
#        --build-arg ROOT_PWD=<root_password> \
#        --build-arg NON_ROOT_PWD=<user_password> \
#        --build-arg NON_ROOT_UID=$(stat -c "%u" .) \
#        --build-arg NON_ROOT_GID=$(stat -c "%g" .) \
#        --build-arg SSHUSER=<user-of-rsync-dest> \
#        --build-arg SSHPASS=<pass-of-rsync-dest> \
#        --build-arg SSHHOST=<host-of-rsync-dest> \
#        --build-arg CRON_TIME_STR="0 0 20 * *" \
#        --build-arg SRC_FILES="<path-to-src-files>" \
#        --build-arg DEST_FOLDER="<path-to-dest-folder>" \
#        --tag sync-pronos:latest .

# CORRER OPERACIONALMENTE CON CRON
# docker run --name sync-pronos \
#        --volume <path-to-src-files-folder>:<path-to-src-files-folder> \
#        --detach sync-pronos:latest



# VER RAM USADA POR LOS CONTENEDORES CORRIENDO
# docker stats --format "table {{.ID}}\t{{.Name}}\t{{.CPUPerc}}\t{{.PIDs}}\t{{.MemUsage}}" --no-stream

# VER LOGS (CON COLORES) DE CONTENEDOR CORRIENDO EN SEGUNDO PLANO
# docker logs --follow ereg 2>&1 | ccze -m ansi
