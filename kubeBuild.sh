#!/bin/bash

# Se déplacer dans le répertoire de déploiement AWS
cd deployment/aws/

# Afficher les déploiements existants
echo "Déploiements actuels :"
kubectl get deploy

# Supprimer les déploiements existants
echo "Suppression des déploiements existants..."
kubectl delete deploy foodcatalogueapp
kubectl delete deploy orderapp
kubectl delete deploy restaurantapp
kubectl delete deploy userapp

# Afficher les services existants
echo "Services actuels :"
kubectl get svc

# Supprimer les services existants
echo "Suppression des services existants..."
kubectl delete svc foodcatalogue-service
kubectl delete svc order-service
kubectl delete svc restaurant-service
kubectl delete svc user-service

# Appliquer les nouvelles configurations
echo "Application des nouvelles configurations..."
kubectl apply -f .

echo "Déploiement terminé."
