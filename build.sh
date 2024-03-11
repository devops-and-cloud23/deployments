#!/bin/bash

# Construire et déployer le service Eureka
cd Eureka/
mvn clean install
docker build -t elfn/eureka-srv:latest .
docker push elfn/eureka-srv:latest

# Construire et déployer le service de catalogue alimentaire
cd ../FoodCatalogue/
mvn clean install
docker build -t elfn/food-catalogue-srv:latest .
docker push elfn/food-catalogue-srv:latest

# Construire et déployer le service de commande
cd ../Order/
mvn clean install
docker build -t elfn/order-srv:latest .
docker push elfn/order-srv:latest

# Construire et déployer le service d'information utilisateur
cd ../UserInformation/
mvn clean install
docker build -t elfn/user-srv:latest .
docker push elfn/user-srv:latest

# Construire et déployer le service de liste des restaurants
cd ../restaurantListing/
mvn clean install
docker build -t elfn/restaurant-srv:latest .
docker push elfn/restaurant-srv:latest
