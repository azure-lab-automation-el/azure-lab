#!/usr/bin/env bash
set -uo pipefail
echo "-- RG resource types --"
az resource list -g rg-learning-monitoring --query '[].{n:name,t:type,sku:sku.name}' -o json
echo "-- cognitive/speech --"
az cognitiveservices account list --query '[].{n:name,g:resourceGroup,kind:kind,sku:sku.name}' -o json 2>&1 | head -20
echo "-- webapps/functionapps --"
az webapp list --query '[].{n:name,g:resourceGroup}' -o json
az functionapp list --query '[].{n:name,g:resourceGroup}' -o json 2>&1 | head -5
echo "-- SWA details --"
az staticwebapp list --query '[].{n:name,g:resourceGroup,sku:sku.name,loc:location,url:defaultHostname}' -o json
