#!/bin/bash

# Параметры проверки
SOURCE_PATH="/mnt/z/"       # Путь к диску Z: в WSL
NAMESPACE="print-serv"      # Namespace в Kubernetes
POD_NAME="nas-cartograms-rsync-pod"  # Имя пода
TARGET_PATH="/data/"        # Целевой путь в контейнере
CHECKSUM_LIMIT=50           # Максимальное количество файлов для проверки контрольных сумм

# Проверка доступности исходного пути
echo "Проверка доступа к исходному пути $SOURCE_PATH..."
if [ ! -d "$SOURCE_PATH" ]; then
    echo "Ошибка: Путь $SOURCE_PATH не существует или недоступен"
    exit 1
fi

# Проверка существования пода
echo "Проверка существования пода $POD_NAME..."
kubectl get pod $POD_NAME -n $NAMESPACE >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "Ошибка: Под $POD_NAME не найден в namespace $NAMESPACE"
    exit 1
fi

# Создание временной директории для результатов проверки
TEMP_DIR=$(mktemp -d)
echo "Создана временная директория для результатов: $TEMP_DIR"

# Получение списка файлов в источнике
echo "Получение списка файлов в источнике..."
find "$SOURCE_PATH" -type f | sort > "$TEMP_DIR/source_files.txt"
SOURCE_FILE_COUNT=$(wc -l < "$TEMP_DIR/source_files.txt")
echo "Найдено $SOURCE_FILE_COUNT файлов в источнике"

# Получение списка файлов в поде
echo "Получение списка файлов в контейнере..."
kubectl exec -n $NAMESPACE $POD_NAME -- find "$TARGET_PATH" -type f | sort > "$TEMP_DIR/target_files.txt"
TARGET_FILE_COUNT=$(wc -l < "$TEMP_DIR/target_files.txt")
echo "Найдено $TARGET_FILE_COUNT файлов в контейнере"

# Сравнение количества файлов
echo "Сравнение количества файлов..."
if [ "$SOURCE_FILE_COUNT" -eq "$TARGET_FILE_COUNT" ]; then
    echo "Количество файлов совпадает: $SOURCE_FILE_COUNT"
else
    echo "ПРЕДУПРЕЖДЕНИЕ: Разное количество файлов!"
    echo "В источнике: $SOURCE_FILE_COUNT"
    echo "В контейнере: $TARGET_FILE_COUNT"
    
    # Ищем отсутствующие файлы
    echo "Анализ различий..."
    
    # Обработка файлов из source_files.txt для сравнения
    cat "$TEMP_DIR/source_files.txt" | sed "s|$SOURCE_PATH||" > "$TEMP_DIR/source_relative.txt"
    
    # Обработка файлов из target_files.txt для сравнения
    cat "$TEMP_DIR/target_files.txt" | sed "s|$TARGET_PATH||" > "$TEMP_DIR/target_relative.txt"
    
    # Поиск отсутствующих файлов
    comm -23 "$TEMP_DIR/source_relative.txt" "$TEMP_DIR/target_relative.txt" > "$TEMP_DIR/missing_in_target.txt"
    MISSING_IN_TARGET=$(wc -l < "$TEMP_DIR/missing_in_target.txt")
    
    comm -13 "$TEMP_DIR/source_relative.txt" "$TEMP_DIR/target_relative.txt" > "$TEMP_DIR/missing_in_source.txt"
    MISSING_IN_SOURCE=$(wc -l < "$TEMP_DIR/missing_in_source.txt")
    
    echo "Файлов, отсутствующих в контейнере: $MISSING_IN_TARGET"
    echo "Файлов, отсутствующих в источнике: $MISSING_IN_SOURCE"
    
    # Вывод первых 10 отсутствующих файлов
    if [ "$MISSING_IN_TARGET" -gt 0 ]; then
        echo "Примеры файлов, отсутствующих в контейнере:"
        head -n 10 "$TEMP_DIR/missing_in_target.txt"
        if [ "$MISSING_IN_TARGET" -gt 10 ]; then
            echo "... и еще $(($MISSING_IN_TARGET - 10)) файлов"
        fi
    fi
    
    if [ "$MISSING_IN_SOURCE" -gt 0 ]; then
        echo "Примеры файлов, отсутствующих в источнике:"
        head -n 10 "$TEMP_DIR/missing_in_source.txt"
        if [ "$MISSING_IN_SOURCE" -gt 10 ]; then
            echo "... и еще $(($MISSING_IN_SOURCE - 10)) файлов"
        fi
    fi
fi

# Проверка контрольных сумм
echo "Начинаем проверку контрольных сумм для выборочных файлов..."

# Выбираем файлы для проверки
cat "$TEMP_DIR/source_relative.txt" | sort -R | head -n $CHECKSUM_LIMIT > "$TEMP_DIR/files_to_check.txt"
CHECK_FILE_COUNT=$(wc -l < "$TEMP_DIR/files_to_check.txt")
echo "Выбрано $CHECK_FILE_COUNT файлов для проверки"

# Рассчитываем контрольные суммы
echo "Рассчитываем контрольные суммы в источнике..."
> "$TEMP_DIR/source_checksums.txt"
while read -r file; do
    md5sum "$SOURCE_PATH/$file" | sed "s|$SOURCE_PATH||" >> "$TEMP_DIR/source_checksums.txt"
done < "$TEMP_DIR/files_to_check.txt"

echo "Рассчитываем контрольные суммы в контейнере..."
> "$TEMP_DIR/target_checksums.txt"
while read -r file; do
    kubectl exec -n $NAMESPACE $POD_NAME -- md5sum "$TARGET_PATH/$file" | sed "s|$TARGET_PATH||" >> "$TEMP_DIR/target_checksums.txt"
done < "$TEMP_DIR/files_to_check.txt"

# Сравниваем контрольные суммы
echo "Сравниваем контрольные суммы..."
DIFF_COUNT=$(diff -y --suppress-common-lines "$TEMP_DIR/source_checksums.txt" "$TEMP_DIR/target_checksums.txt" | wc -l)

if [ "$DIFF_COUNT" -eq 0 ]; then
    echo "Все контрольные суммы совпадают. Файлы идентичны."
else
    echo "ПРЕДУПРЕЖДЕНИЕ: Обнаружены различия в контрольных суммах для $DIFF_COUNT файлов."
    echo "Файлы с различиями:"
    diff -y --suppress-common-lines "$TEMP_DIR/source_checksums.txt" "$TEMP_DIR/target_checksums.txt"
fi

# Очистка
echo "Удаление временных файлов..."
rm -rf "$TEMP_DIR"

echo "Проверка завершена."
if [ "$SOURCE_FILE_COUNT" -eq "$TARGET_FILE_COUNT" ] && [ "$DIFF_COUNT" -eq 0 ]; then
    echo "Результат: Успешная синхронизация. Данные идентичны."
    exit 0
else
    echo "Результат: Обнаружены различия между источником и контейнером."
    exit 1
fi 