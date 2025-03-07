# Перенос данных в PVC Kubernetes

Этот проект содержит скрипты для переноса большого объема данных (~900+ папок, 500+ ГБ) с сетевого диска Windows в Persistent Volume Claim (PVC) в кластере Kubernetes с поддержкой кириллических имен файлов.

## Описание решения

После тестирования различных методов, наиболее эффективным подходом оказалось использование **Windows Subsystem for Linux (WSL)** для синхронизации данных. Решение позволяет корректно обрабатывать файлы с кириллическими именами, обеспечивает надежную и быструю передачу данных.

### Преимущества использования WSL

1. **Корректная работа с кириллицей**: Linux-окружение лучше обрабатывает UTF-8, что решает проблемы с именами файлов на русском языке
2. **Нативные Linux-инструменты**: `rsync`, `ssh`, `md5sum` работают без дополнительных настроек
3. **Высокая скорость передачи данных**: Эффективное использование инкрементальной синхронизации
4. **Возможность проверки целостности**: Проверка количества файлов и контрольных сумм

## Структура проекта

- `sync-wsl.sh` - Скрипт для синхронизации данных через WSL
- `verify-wsl.sh` - Скрипт для проверки целостности данных
- `wsl-sync.ps1` - PowerShell-обертка для запуска скриптов из Windows
- `nas-cartograms-pvc.yaml` - Манифест для создания PVC в Kubernetes
- `nas-cartograms-rsync-pod.yaml` - Манифест для создания пода
- `Dockerfile` - Для создания образа контейнера
- `supervisord.conf` - Конфигурация для контейнера

## Быстрый старт

### Предварительные требования

- Windows 10/11 с поддержкой WSL 2
- Ubuntu в WSL
- Установленный `kubectl` с настроенным доступом к кластеру Kubernetes
- Доступ к сетевому ресурсу (UNC-путь или сетевой диск)

### Шаг 1: Установка WSL и Ubuntu

```powershell
wsl --install -d Ubuntu
```

### Шаг 2: Настройка Ubuntu

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y rsync openssh-client locales
sudo locale-gen ru_RU.UTF-8
echo 'export LANG=ru_RU.UTF-8' >> ~/.bashrc
source ~/.bashrc
```

### Шаг 3: Монтирование сетевого ресурса

```bash
# Рекомендуемый способ - через UNC-путь
sudo mkdir -p /mnt/share
sudo mount -t drvfs '\\\\<server-name>\\<share-name>' /mnt/share -o metadata

# Альтернативный способ - через букву диска (если доступно)
sudo mkdir -p /mnt/z
sudo mount -t drvfs Z: /mnt/z -o metadata
```

### Шаг 4: Настройка доступа к Kubernetes

```bash
# Создание директории для kubectl
mkdir -p ~/.kube

# Копирование конфигурации из Windows
cp /mnt/c/Users/<username>/.kube/config ~/.kube/

# Настройка alias для kubectl в Windows
echo 'alias kubectl="/mnt/c/Program\ Files/Docker/Docker/resources/bin/kubectl.exe"' >> ~/.bashrc
source ~/.bashrc
```

### Шаг 5: Запуск скриптов

```bash
# Создание PVC и пода в Kubernetes (если еще не созданы)
kubectl apply -f nas-cartograms-pvc.yaml -n print-serv
kubectl apply -f nas-cartograms-rsync-pod.yaml -n print-serv

# Запуск синхронизации
./sync-wsl.sh

# Проверка результатов
./verify-wsl.sh
```

## Использование PowerShell-обертки

Для запуска скрипта синхронизации из Windows без входа в WSL:

```powershell
# Запуск синхронизации
.\wsl-sync.ps1

# Запуск проверки
.\wsl-sync.ps1 -Verify
```

## Подробное руководство

### Настройка параметров в скриптах

Скрипты имеют конфигурируемые параметры в начале файла:

- `SOURCE_PATH` - путь к источнику данных (например, "/mnt/share/")
- `NAMESPACE` - Kubernetes namespace
- `POD_NAME` - имя пода
- `LOCAL_PORT` - порт для SSH проброса
- `TARGET_PATH` - целевой путь в контейнере

Вы можете изменить эти параметры, отредактировав скрипт:

```bash
nano sync-wsl.sh
# Внесите изменения и сохраните (Ctrl+O, затем Enter, Ctrl+X)
```

### Проверка результатов синхронизации

Для проверки состояния синхронизации:

```bash
# Подсчет общего количества файлов
kubectl exec -n print-serv nas-cartograms-rsync-pod -- find /data -type f | wc -l

# Подсчет общего количества директорий
kubectl exec -n print-serv nas-cartograms-rsync-pod -- find /data -type d | wc -l

# Проверка использованного места на диске
kubectl exec -n print-serv nas-cartograms-rsync-pod -- du -sh /data
```

## Решение проблем

### Проблемы с доступом к сетевой шаре

Если стандартное монтирование не работает:

```bash
# Монтирование с дополнительными опциями
sudo mount -t drvfs '\\\\<server>\\<share>' /mnt/share -o metadata,uid=$(id -u),gid=$(id -g)
```

### Проблемы с кодировкой имен файлов

Проверьте настройки локали:

```bash
# Проверка текущей локали
locale

# Должна отображаться ru_RU.UTF-8
# Если нет - настройте локаль:
sudo locale-gen ru_RU.UTF-8
export LANG=ru_RU.UTF-8
```

### Проблемы с kubectl

Если kubectl недоступен в WSL:

```bash
# Установка kubectl в WSL
sudo apt update
sudo apt install -y apt-transport-https ca-certificates curl
curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-archive-keyring.gpg] https://apt.kubernetes.io/ kubernetes-xenial main" | sudo tee /etc/apt/sources.list.d/kubernetes.list
sudo apt update
sudo apt install -y kubectl

# Если проще, используйте kubectl из Windows
"/mnt/c/Program Files/Docker/Docker/resources/bin/kubectl.exe" get namespaces
```

## Техническая информация

### Принцип работы

1. Скрипт устанавливает проброс портов к поду в Kubernetes через kubectl
2. Через SSH запускается rsync для синхронизации данных
3. Поддерживаются инкрементальные обновления - повторный запуск скрипта передаст только изменения

### Мониторинг процесса

Выход из скрипта не прерывает синхронизацию. Для проверки состояния процесса используйте:

```bash
# Проверка, запущен ли rsync
kubectl exec -n print-serv nas-cartograms-rsync-pod -- ps aux | grep rsync

# Проверка последних скопированных файлов
kubectl exec -n print-serv nas-cartograms-rsync-pod -- find /data -type f -mtime -1 | head
``` 