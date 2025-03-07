#!/bin/bash

# Параметры синхронизации
SOURCE_PATH="/mnt/z/"       # Путь к диску Z: в WSL
NAMESPACE="print-serv"      # Namespace в Kubernetes
POD_NAME="nas-cartograms-rsync-pod"  # Имя пода
LOCAL_PORT=2222             # Порт для проброса SSH
TARGET_PATH="/data/"        # Целевой путь в контейнере

# Проверка доступности исходного пути
echo "Проверка доступа к исходному пути $SOURCE_PATH..."
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Ошибка: Путь $SOURCE_PATH не существует или недоступен"
    
    # Попытка автоматического монтирования, если не смонтирован
    echo "Попытка монтирования диска Z:..."
    sudo mkdir -p /mnt/z
    sudo mount -t drvfs Z: /mnt/z -o metadata
    
    if [ ! -d "$SOURCE_PATH" ]; then
        echo "Ошибка: Не удалось смонтировать диск Z:"
        echo "Альтернативный вариант - использовать UNC-путь напрямую:"
        echo "sudo mkdir -p /mnt/share"
        echo "sudo mount -t drvfs '\\\\3-169\\izuch_lib' /mnt/share"
        exit 1
    fi
    
    echo "Диск Z: успешно смонтирован"
fi

# Проверка наличия rsync и ssh
command -v rsync >/dev/null 2>&1 || { echo "Ошибка: rsync не установлен. Установите его: sudo apt install rsync"; exit 1; }
command -v ssh >/dev/null 2>&1 || { echo "Ошибка: ssh не установлен. Установите его: sudo apt install openssh-client"; exit 1; }

# Проверка доступа к кластеру Kubernetes
echo "Проверка доступа к кластеру Kubernetes..."
kubectl get namespace $NAMESPACE >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Ошибка: Не удалось получить доступ к namespace $NAMESPACE"
    echo "Убедитесь, что у вас настроен kubectl и есть доступ к кластеру"
    exit 1
fi

# Проверка существования пода
echo "Проверка существования пода $POD_NAME..."
kubectl get pod $POD_NAME -n $NAMESPACE >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Ошибка: Под $POD_NAME не найден в namespace $NAMESPACE"
    exit 1
fi

# Запуск проброса портов в фоновом режиме
echo "Настройка проброса портов (порт $LOCAL_PORT -> порт 22 в контейнере)..."
kubectl port-forward pod/$POD_NAME $LOCAL_PORT:22 -n $NAMESPACE &
PORT_FORWARD_PID=$!

# Ожидание установки соединения
echo "Ожидание установки соединения..."
sleep 5

# Проверка, работает ли проброс портов
if ! ps -p $PORT_FORWARD_PID > /dev/null; then
    echo "Ошибка: Не удалось установить проброс портов"
    exit 1
fi

# Настройка опций для rsync и ssh
SSH_OPTS="-p $LOCAL_PORT -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
RSYNC_OPTS="-avz --progress --stats --delete"

# Проверка локали для корректной работы с кириллицей
CURRENT_LOCALE=$(locale | grep "LANG=" | cut -d= -f2)
if [[ $CURRENT_LOCALE != *"UTF-8"* ]]; then
    echo "Предупреждение: Текущая локаль ($CURRENT_LOCALE) может не поддерживать кириллицу"
    echo "Рекомендуется использовать UTF-8 локаль, например ru_RU.UTF-8"
    echo "Вы можете настроить её командами:"
    echo "  sudo apt install locales"
    echo "  sudo locale-gen ru_RU.UTF-8"
    echo "  export LANG=ru_RU.UTF-8"
    echo ""
    echo "Продолжить синхронизацию? (y/n)"
    read -r CONTINUE
    if [[ ! $CONTINUE =~ ^[Yy]$ ]]; then
        echo "Синхронизация отменена"
        kill $PORT_FORWARD_PID
        exit 1
    fi
fi

# Запуск rsync
echo "Запуск синхронизации данных..."
echo "Из: $SOURCE_PATH"
echo "В: root@localhost:$TARGET_PATH (через порт $LOCAL_PORT)"
echo "Команда: rsync $RSYNC_OPTS -e \"ssh $SSH_OPTS\" \"$SOURCE_PATH\" root@localhost:\"$TARGET_PATH\""

rsync $RSYNC_OPTS -e "ssh $SSH_OPTS" "$SOURCE_PATH" root@localhost:"$TARGET_PATH"
RSYNC_EXIT_CODE=$?

# Остановка проброса портов
echo "Остановка проброса портов..."
kill $PORT_FORWARD_PID

# Проверка результата
if [ $RSYNC_EXIT_CODE -eq 0 ]; then
    echo "Синхронизация успешно завершена!"
elif [ $RSYNC_EXIT_CODE -eq 23 ]; then
    echo "Синхронизация завершена с предупреждениями (код 23)"
    echo "Некоторые файлы не удалось передать, но в целом синхронизация успешна"
else
    echo "Ошибка при синхронизации (код $RSYNC_EXIT_CODE)"
fi

echo "Для проверки результатов выполните:"
echo "kubectl exec -n $NAMESPACE $POD_NAME -- ls -la $TARGET_PATH"

exit $RSYNC_EXIT_CODE 