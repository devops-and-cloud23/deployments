#!/bin/bash

 # Identifier de l'instance RDS pour laquelle créer l'instantané
    DB_INSTANCE_IDENTIFIER="mysql-db"
  # Identifier unique pour l'instantané RDS
    SNAPSHOT_IDENTIFIER="mysql-db-snapshot-$(date +%F-%H-%M-%S)"
  
   
  # Nom de la stack CloudFormation
    STACK_NAME="eksctl-aws-eks-cluster-cluster"
    REGION="us-east-2" # La région de votre cluster EKS
    CLUSTER_NAME="aws-eks-cluster" # Le nom de votre cluster EKS
    BACKUP_FILE="eks/backup-$(date +%Y%m%d%H%M%S).yaml" # Définissez le fichier de sauvegarde avec un timestamp
   GLOBAL_LB_NAME=$(kubectl get ingress aws-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')


#1- EKS Creation commands
ekscrt(){
        # Nom de la stack CloudFormation
    STACK_NAME="eksctl-aws-eks-cluster-cluster"

    # Vérifier si la stack CloudFormation existe
    STACK_EXISTS=$(aws cloudformation describe-stacks --stack-name $STACK_NAME --region us-east-2 --query "Stacks[?StackName=='$STACK_NAME'].StackName" --output text)

   # Suppression de toutes les stacks CloudFormation liées au EKS
    echo "Recherche de toutes les stacks CloudFormation liées au cluster EKS..."
    STACKS_TO_DELETE=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName,'$CLUSTER_NAME')].StackName" --output text)

    if [ -n "$STACKS_TO_DELETE" ]; then
    for STACK_NAME in $STACKS_TO_DELETE; do
        echo "Suppression de la stack CloudFormation $STACK_NAME..."
        aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
        echo "Attente de la suppression de la stack $STACK_NAME..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
    done
    else
    echo "Aucune stack CloudFormation liée au cluster EKS $CLUSTER_NAME à supprimer."
    fi

    # Créer le cluster EKS
    echo "Création du cluster EKS..."
    eksctl create cluster --name aws-eks-cluster --region us-east-2 --nodegroup-name eks-cluster-node --node-type t3.medium --nodes 1

    # Mettre à jour le fichier kubeconfig avec le nouveau cluster EKS
    # Pour la connection et l'interaction avec le cluster
    echo "Mise à jour du kubeconfig..."
    aws eks --region $REGION update-kubeconfig --name aws-eks-cluster

    # Créer un nouveau groupe de nœuds
    echo "Création d'un groupe de nœuds..."
    eksctl create nodegroup --cluster $CLUSTER_NAME --region $REGION --name node-grp

    # Deploiement des services dans le cluster
    echo "Deploiement des différents services..."
    cd aws
    ./kubeBuild.sh

    # Appliquer la configuration Kubernetes pour les sauvegardes
    # echo "Application de la configuration de sauvegarde Kubernetes..."
    # kubectl apply -f $BACKUP_FILE

    echo "Le script a terminé son exécution."
}

#2- Commandes de suppression EKS
eksdlt() {
  CLUSTER_NAME="aws-eks-cluster" # Mettez à jour cela avec le nom de votre cluster EKS
  BACKUP_FILE="backup-$(date +%Y%m%d%H%M%S).yaml" # Nom de fichier pour la sauvegarde

  # Créer une sauvegarde des ressources de tous les namespaces
 # echo "Création d'une sauvegarde des ressources..."
 # kubectl get all --all-namespaces -o yaml > $BACKUP_FILE

  # Suppression de toutes les stacks CloudFormation liées au EKS
    echo "Recherche de toutes les stacks CloudFormation liées au cluster EKS..."
    STACKS_TO_DELETE=$(aws cloudformation list-stacks --region $REGION --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query "StackSummaries[?contains(StackName,'$CLUSTER_NAME')].StackName" --output text)

    if [ -n "$STACKS_TO_DELETE" ]; then
    for STACK_NAME in $STACKS_TO_DELETE; do
        echo "Suppression de la stack CloudFormation $STACK_NAME..."
        aws cloudformation delete-stack --stack-name $STACK_NAME --region $REGION
        echo "Attente de la suppression de la stack $STACK_NAME..."
        aws cloudformation wait stack-delete-complete --stack-name $STACK_NAME --region $REGION
    done
    else
    echo "Aucune stack CloudFormation liée au cluster EKS $CLUSTER_NAME à supprimer."
    fi

  # Suppression des groupes de nœuds
  echo "Début de la suppression des groupes de nœuds..."
  NODE_GROUPS=$(eksctl get nodegroup --cluster $CLUSTER_NAME --region $REGION | awk 'NR>1{print $2}')
  if [ -z "$NODE_GROUPS" ]; then
    echo "Aucun groupe de nœuds trouvé."
  else
    for NODE_GROUP in $NODE_GROUPS; do
      echo "Suppression du groupe de nœuds $NODE_GROUP du cluster $CLUSTER_NAME..."
      eksctl delete nodegroup --cluster $CLUSTER_NAME --name "$NODE_GROUP" --region $REGION --wait
    done
    echo "Tous les groupes de nœuds ont été supprimés."
  fi

  # Suppression du cluster EKS
  echo "Suppression du cluster EKS $CLUSTER_NAME..."
  eksctl delete cluster --name $CLUSTER_NAME --region $REGION --wait

  echo "Le cluster $CLUSTER_NAME a été supprimé."
}




#3- RDS snaphot
rdsSave() {

  echo "Vérification de l'existence de l'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}'..."

  # Vérifier si l'instance RDS existe
  INSTANCE_EXISTS=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null)

  if [ "$INSTANCE_EXISTS" == "$DB_INSTANCE_IDENTIFIER" ]; then
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' existe."
    echo "Création d'un instantané de la base de données RDS '${DB_INSTANCE_IDENTIFIER}'..."

    # Créer un instantané RDS
    aws rds create-db-snapshot --db-snapshot-identifier $SNAPSHOT_IDENTIFIER --db-instance-identifier $DB_INSTANCE_IDENTIFIER

    echo "L'instantané '${SNAPSHOT_IDENTIFIER}' a été créé avec succès."
  else
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' n'existe pas. Impossible de créer l'instantané."
  fi
}

#4- RDS recovering
rdsrcv() {
#   DB_INSTANCE_IDENTIFIER="mysql-rds" # Remplacez par votre identifiant d'instance
#   SNAPSHOT_IDENTIFIER="mysql-rds-snapshot" # Remplacez par votre identifiant d'instantané

  echo "Vérification de l'existence de l'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' avant la restauration..."

  # Vérifier si l'instance RDS existe
  INSTANCE_EXISTS=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null)

  if [ -n "$INSTANCE_EXISTS" ]; then
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' existe déjà. La restauration n'est pas nécessaire."
  else
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' n'existe pas. Début de la restauration..."
    aws rds restore-db-instance-from-db-snapshot --db-instance-identifier $DB_INSTANCE_IDENTIFIER --db-snapshot-identifier $SNAPSHOT_IDENTIFIER
    echo "La restauration de l'instance RDS '${DB_INSTANCE_IDENTIFIER}' à partir de l'instantané '${SNAPSHOT_IDENTIFIER}' a été lancée."
  fi
}


#5- RDS Creation
rdsCrt() {

  echo "Vérification de l'existence de l'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}'..."

  # Vérifier si l'instance RDS existe
  INSTANCE_EXISTS=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null)

  if [ "$INSTANCE_EXISTS" == "$DB_INSTANCE_IDENTIFIER" ]; then
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' existe déjà. Aucune action créée."
  else
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' n'existe pas. Création de l'instance..."
    # Créer une nouvelle instance RDS
    aws rds create-db-instance \
        --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
        --db-instance-class db.t3.micro \
        --engine mysql \
        --engine-version "8.0.36" \
        --allocated-storage 20 \
        --master-username admin \
        --master-user-password elimane1991 \
        --backup-retention-period 7 \
        --tags Key=Name,Value=MonInstanceMySQLFreeTier \
        --region us-east-2

    echo "L'instance '${DB_INSTANCE_IDENTIFIER}' a été créée avec succès."
  fi
}


#6- RDS deletion
rdsDlt() {

  echo "Vérification de l'existence de l'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}'..."

  # Vérifier si l'instance RDS existe
  INSTANCE_EXISTS=$(aws rds describe-db-instances --db-instance-identifier $DB_INSTANCE_IDENTIFIER --region us-east-2 --query 'DBInstances[0].DBInstanceIdentifier' --output text 2>/dev/null)

  if [ -n "$INSTANCE_EXISTS" ]; then
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' existe. Suppression en cours..."
    # Supprimer l'instance RDS sans créer d'instantané final
    aws rds delete-db-instance \
        --db-instance-identifier $DB_INSTANCE_IDENTIFIER \
        --skip-final-snapshot \
        --region us-east-2
    echo "La suppression de l'instance '${DB_INSTANCE_IDENTIFIER}' a été lancée. La suppression peut prendre quelques minutes."
  else
    echo "L'instance de base de données RDS '${DB_INSTANCE_IDENTIFIER}' n'existe pas ou a déjà été supprimée."
  fi
}



#7- Load balancer creation
lbCrt() {
    
# Crée une politique IAM qui définit les permissions nécessaires pour le contrôleur d'équilibrage de charge AWS afin de gérer les ressources ALB pour le cluster EKS.
echo "Création de la politique IAM pour le contrôleur de load balancer..."
aws iam create-policy --policy-name AWSLoadBalancerControllerIAMPolicy --policy-document file://documents/iam_policy.json --region $REGION

# Associe le fournisseur d'identité OIDC d'IAM avec le cluster EKS, permettant l'authentification basée sur les rôles IAM pour les services dans le cluster.
echo "Association du fournisseur OIDC IAM avec le cluster EKS..."
eksctl utils associate-iam-oidc-provider --region=$REGION --cluster=$CLUSTER_NAME --approve

# Crée un compte de service IAM spécifique pour le contrôleur d'équilibrage de charge dans Kubernetes, et lui attribue la politique IAM créée précédemment, permettant au contrôleur d'interagir avec les ressources ALB.
echo "Création du compte de service IAM pour le contrôleur de load balancer..."
eksctl create iamserviceaccount --cluster=$CLUSTER_NAME --namespace=kube-system --region $REGION --name=aws-load-balancer-controller --role-name AmazonEKSLoadBalancerControllerRole --attach-policy-arn=arn:aws:iam::654654413024:policy/AWSLoadBalancerControllerIAMPolicy --override-existing-serviceaccounts --approve

# Déploie Cert-Manager dans le cluster Kubernetes, un outil nécessaire pour la gestion des certificats TLS utilisés par les ingress, y compris ceux gérés par le contrôleur d'équilibrage de charge AWS.
echo "Déploiement de Cert-Manager..."
kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.3/cert-manager.yaml


  echo "Application de la configuration du contrôleur de load balancer..."
  kubectl apply -f documents/v2_5_4_full.yaml

  echo "Configuration du contrôleur de load balancer terminée."

  # Attendre que l'Ingress soit complètement déployé et que l'équilibreur de charge soit créé
  echo "Attente de la création de l'équilibreur de charge..."
  sleep 60 # Attendre 60 secondes pour laisser le temps à l'équilibreur de charge de se déployer

# echo "Création de la classe d'Ingress..."
  kubectl apply -f ingress-class.yaml

# echo "Création des règles d'Ingress..."
  kubectl apply -f ingress.yaml

  GLOBAL_LB_NAME=$(kubectl get ingress aws-ingress -o jsonpath='{.status.loadBalancer.ingress[*].hostname}')

   # Afficher le nom de l'équilibreur de charge
  # Remplacer `<votre-ingress>` par le nom réel de votre ressource Ingress
  echo "Nom de l'équilibreur de charge créé : $GLOBAL_LB_NAME"

  # Stocker LB_NAME dans une variable globale
  # GLOBAL_LB_NAME=$LB_NAME
}

#8- RDS snapshot suppression
rdsSnpDlt() {

  echo "Vérification de l'existence de l'instantané RDS '${SNAPSHOT_IDENTIFIER}'..."

  # Vérifier si l'instantané RDS existe
  SNAPSHOT_EXISTS=$(aws rds describe-db-snapshots --db-snapshot-identifier $SNAPSHOT_IDENTIFIER --query 'DBSnapshots[0].DBSnapshotIdentifier' --output text 2>/dev/null)

  if [ "$SNAPSHOT_EXISTS" == "$SNAPSHOT_IDENTIFIER" ]; then
    echo "L'instantané RDS '${SNAPSHOT_IDENTIFIER}' existe. Suppression en cours..."
    # Supprimer l'instantané RDS
    aws rds delete-db-snapshot --db-snapshot-identifier $SNAPSHOT_IDENTIFIER
    echo "La suppression de l'instantané '${SNAPSHOT_IDENTIFIER}' a été lancée. La suppression peut prendre quelques minutes."
  else
    echo "L'instantané RDS '${SNAPSHOT_IDENTIFIER}' n'existe pas ou a déjà été supprimé."
  fi
}

#9- Load balancer suppression
lbDlt() {
   
    LB_ARN=$(aws elbv2 describe-load-balancers --region $REGION --query "LoadBalancers[?DNSName=='$GLOBAL_LB_NAME'].LoadBalancerArn" --output text)

  if [ -n "$GLOBAL_LB_NAME" ]; then
    echo "Suppression de l'équilibreur de charge : $GLOBAL_LB_NAME"
    # Ici, ajoutez la commande pour supprimer l'équilibreur de charge
    # La commande spécifique dépend de comment vous avez créé l'équilibreur de charge.
    # Par exemple, si vous l'avez créé via un service Kubernetes de type LoadBalancer, vous pourriez devoir supprimer ce service.
    kubectl delete ingress aws-ingress
    # Assurez-vous de remplacer <votre-ingress> par le nom réel de votre ressource Ingress
     echo "Suppression de l'équilibreur de charge avec l'ARN $LB_ARN dans la région $REGION..."
  
    aws elbv2 delete-load-balancer --load-balancer-arn $LB_ARN --region $REGION
  
     echo "L'équilibreur de charge a été supprimé."
  else
    echo "Aucun équilibreur de charge à supprimer."
  fi
}





# Ici, vos définitions de fonctions...

# Utilisation de switch case pour exécuter la fonction correspondante basée sur l'argument fourni.
# Ceci permet une gestion flexible et une extension facile du script pour inclure d'autres fonctions à l'avenir.
# Pour utiliser, exécutez ce script avec l'un des arguments suivants :
# ekscrt - Pour créer un cluster EKS
# eksdlt - Pour supprimer un cluster EKS
# rdsSave - Pour sauvegarder une instance RDS
# rdsrcv - Pour restaurer une instance RDS à partir d'un snapshot
# rdsCrt - Pour créer une instance RDS
# rdsDlt - Pour supprimer une instance RDS
# lbCrt - Pour configurer un équilibreur de charge
# rdsSnpDlt -  Pour supprimer le snapshot d'une instance RDS
# lbDlt - Suppression de l'équilibreur de charge
case "$1" in
  ekscrt)
    ekscrt
    ;;
  eksdlt)
    eksdlt
    ;;
  rdssave)
    rdsSave
    ;;
  rdsrcv)
    rdsrcv
    ;;
  rdscrt)
    rdsCrt
    ;;
  rdsdlt)
    rdsDlt
    ;;
  lbcrt)
    lbCrt
    ;;
  lbdlt)
    lbDlt
    ;;
  rdssnpdlt)
    rdsSnpDlt
    ;;
  *)
    echo "Argument non reconnu. Les options disponibles sont : ekscrt, eksdlt, rdssave, rdsrcv, rdscrt, rdsdlt, lbcrt."
    ;;
esac
