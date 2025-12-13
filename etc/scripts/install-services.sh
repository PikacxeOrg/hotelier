#!/bin/bash

helm install accommodation infrastructure/helm/accommodation-service -n default
helm install availability infrastructure/helm/availability-service -n default
helm install identity infrastructure/helm/identity-service -n default
helm install notification infrastructure/helm/notification-service -n default
helm install rating infrastructure/helm/rating-service -n default
helm install reservation infrastructure/helm/reservation-service -n default
helm install search infrastructure/helm/search-service -n default
helm install cdn infrastructure/helm/cdn-service -n default