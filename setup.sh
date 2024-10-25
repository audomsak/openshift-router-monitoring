#!/bin/bash

PROJECT=grafana

####################################################
# Functions
####################################################

repeat() {
    echo
    for i in {1..120}; do
        echo -n "$1"
    done
    echo
}

install_operator() {
    operatorNameParam=$1
    operatorDescParam=$2
    ymlFilePathParam=$3
    project=$4

    echo
    echo "Installing $operatorDescParam to $project project..."
    echo

    oc apply -f $ymlFilePathParam -n $project
    oc wait --for=jsonpath='{.status.components.refs[?(@.apiVersion=="apps/v1")].conditions[?(@.type=="Available")].status}'=True \
       operators/$operatorNameParam.$project --timeout=300s -n $project
}

create_project() {
    echo
    echo "Creating $PROJECT project..."
    echo

    oc new-project $PROJECT
}

create_operator_group() {
    echo
    echo "Creating OperatorGroup custom resource (CR) in $PROJECT project..."
    echo

    cat operator-group.yml | sed "s#NAMESPACE#$PROJECT#g" | oc apply -n $PROJECT -f -
}

install_grafana() {
    operatorName=grafana-operator
    operatorDesc="Grafana Operator"
    ymlFilePath=grafana-subscription.yml
    project=$PROJECT

    install_operator $operatorName "$operatorDesc" $ymlFilePath $project
}

add_monitoring_view_role() {
    echo ""
    echo "Add monitoring view role to Grafana service account..."
    echo

    oc adm policy add-cluster-role-to-user cluster-monitoring-view -z grafana-sa -n $PROJECT
}

create_grafana_instance() {
    echo
    echo "Creating Grafana custom resource (CR) in $PROJECT project..."
    echo

    oc apply -f grafana.yml -n $PROJECT
    oc wait --for=jsonpath='{.status.stage}'=complete grafanas/grafana --timeout=300s -n $PROJECT

    podname=`oc get pods --no-headers -o custom-columns=":metadata.name" -l app=grafana -n $PROJECT`
    oc wait --for=condition=Ready=True pods/$podname --timeout=300s -n $PROJECT
}

create_grafana_datasource() {
    echo
    echo "Creating GrafanaDatasource custom resource (CR) in $PROJECT project..."
    echo

    #Create 1-year token for Grafana service account to be used for Thanos Querier authentication
    token=`oc create token grafana-sa --duration 8765h -n $PROJECT`
    cat grafana-datasource.yml | sed "s#TOKEN#$token#g" | oc apply -n $PROJECT -f -
    oc wait --for=jsonpath='{.status.lastResync}' grafanadatasources/grafana-datasource --timeout=300s -n $PROJECT
}

create_grafana_dashboard() {
    echo
    echo "Creating GrafanaDashboard custom resource (CR) in $PROJECT project..."
    echo
}

print_info() {
    route=`oc get route grafana-route -o jsonpath='{.spec.host}' -n $PROJECT`

    echo
    echo "Grafana Web Console: https://$route"
    echo "Username: admin"
    echo "Password: admin"
    echo
}

####################################################
# Main (Entry point)
####################################################
echo
echo "Setting up Grafana instance..."
repeat '-'

create_project
repeat '-'

create_operator_group
repeat '-'

install_grafana
repeat '-'

create_grafana_instance
repeat '-'

add_monitoring_view_role
repeat '-'

create_grafana_datasource
repeat '-'

create_grafana_dashboard
repeat '-'

print_info
