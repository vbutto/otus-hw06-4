#!/bin/bash

# Скрипт для развертывания приложения в Yandex Managed Kubernetes
# Образ должен быть предварительно загружен в Container Registry

set -e

# Цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Функция для вывода сообщений
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Переменные (настройте под свой проект)
REGISTRY_NAME="hw06-cr-demo"
IMAGE_NAME="hw06-app"
IMAGE_TAG="${1:-1.0}"
FULL_IMAGE_NAME="${REGISTRY_NAME}.cr.yandex/${IMAGE_NAME}:${IMAGE_TAG}"

log "🚀 Развертывание приложения в Kubernetes"
log "Registry: $REGISTRY_NAME"
log "Image: $IMAGE_NAME:$IMAGE_TAG"

# Проверяем наличие deployment файла
log "📋 Проверяем файлы..."
if [[ ! -f "deployment.yaml" ]]; then
    error "Файл deployment.yaml не найден!"
    exit 1
fi

# Проверяем, что образ существует в registry
log "🔍 Проверяем наличие образа в Container Registry..."
if ! yc container image list --registry-name=$REGISTRY_NAME --format=json | jq -e ".[] | select(.tags[] == \"$IMAGE_TAG\")" > /dev/null; then
    error "❌ Образ $FULL_IMAGE_NAME не найден в registry!"
    error "Загрузите образ в registry перед развертыванием"
    exit 1
else
    log "✅ Образ $FULL_IMAGE_NAME найден в registry"
fi

# Проверяем подключение к кластеру
log "☸️  Проверяем подключение к Kubernetes кластеру..."
if ! kubectl cluster-info > /dev/null 2>&1; then
    warn "❌ Нет подключения к кластеру!"
    log "Получаем kubeconfig..."
    
    # Пытаемся получить kubeconfig автоматически
    CLUSTER_NAME=$(yc managed-kubernetes cluster list --format json | jq -r '.[0].name // empty')
    
    if [[ -n "$CLUSTER_NAME" ]]; then
        log "Найден кластер: $CLUSTER_NAME"
        yc managed-kubernetes cluster get-credentials $CLUSTER_NAME --external --force
    else
        error "Кластер не найден! Создайте кластер или получите kubeconfig вручную:"
        error "yc managed-kubernetes cluster get-credentials <CLUSTER_NAME> --external --force"
        exit 1
    fi
fi

# Проверяем узлы кластера
log "📊 Проверяем состояние кластера..."
kubectl get nodes -o wide

# Обновляем deployment.yaml с правильным именем образа
log "📝 Обновляем конфигурацию deployment..."
sed -i.bak "s|hw06-cr-demo.cr.yandex/hw06-app:.*|$FULL_IMAGE_NAME|g" deployment.yaml

# Применяем манифесты
log "🚀 Развертываем приложение в Kubernetes..."
kubectl apply -f deployment.yaml

if [[ $? -eq 0 ]]; then
    log "✅ Приложение успешно развернуто"
else
    error "❌ Ошибка при развертывании"
    exit 1
fi

# Ждем готовности подов
log "⏳ Ожидаем готовности подов..."
kubectl wait --for=condition=ready pod -l app=hw06-app --timeout=300s

# Проверяем статус развертывания
log "📋 Статус развертывания:"
kubectl get deployments,pods,services -l app=hw06-app

# Получаем внешний IP LoadBalancer'а
log "🌐 Получаем внешний IP сервиса..."
EXTERNAL_IP=""
COUNTER=0
MAX_ATTEMPTS=60

while [[ -z "$EXTERNAL_IP" && $COUNTER -lt $MAX_ATTEMPTS ]]; do
    echo -n "."
    EXTERNAL_IP=$(kubectl get svc hw06-app-service -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    if [[ -z "$EXTERNAL_IP" ]]; then
        sleep 5
        ((COUNTER++))
    fi
done
echo ""

if [[ -n "$EXTERNAL_IP" ]]; then
    log "🎉 Приложение доступно по адресу: http://$EXTERNAL_IP"
    log "🏥 Health check: http://$EXTERNAL_IP/health"
    
    # Тестируем приложение
    log "🧪 Тестируем приложение..."
    echo ""
    echo "=== Основная страница ==="
    curl -s "http://$EXTERNAL_IP" || warn "Не удалось получить ответ"
    echo ""
    echo "=== Health check ==="
    curl -s "http://$EXTERNAL_IP/health" || warn "Health check недоступен"
    echo ""
    
else
    warn "⚠️  Внешний IP еще не назначен. Проверьте позже:"
    warn "kubectl get svc hw06-app-service"
fi

# Полезные команды для мониторинга
log "📊 Полезные команды для мониторинга:"
echo ""
echo "# Статус подов:"
echo "kubectl get pods -l app=hw06-app"
echo ""
echo "# Логи приложения:"
echo "kubectl logs -f deployment/hw06-app"
echo ""
echo "# Описание сервиса:"
echo "kubectl describe svc hw06-app-service"
echo ""
echo "# Удалить приложение:"
echo "kubectl delete -f deployment.yaml"
echo ""

log "✨ Развертывание завершено!"