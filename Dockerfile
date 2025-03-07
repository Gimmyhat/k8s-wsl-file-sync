FROM ubuntu:22.04

# Установка необходимых пакетов
RUN apt-get update && \
    apt-get install -y openssh-server rsync supervisor && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Настройка SSH
RUN mkdir /var/run/sshd
RUN echo 'root:password' | chpasswd
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config

# Создаем директорию для данных
RUN mkdir -p /data

# Настройка Supervisor
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Экспозиция SSH порта
EXPOSE 22

# Запуск Supervisor
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"] 