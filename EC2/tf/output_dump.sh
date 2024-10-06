#!/bin/bash
ENV_PATH=../.env

terraform output > $ENV_PATH
sed -i -e 's/ = /=/g' $ENV_PATH
