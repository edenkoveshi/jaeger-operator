#!/bin/bash

source $(dirname "$0")/../render-utils.sh


start_test "es-index-cleaner"
export JAEGER_NAME="test-es-index-cleaner-with-prefix"
export CRONJOB_NAME="test-es-index-cleaner-with-prefix-es-index-cleaner"

# Install Elasticsearch instance
render_install_elasticsearch "00"

# Create and assert the Jaeger instance with index cleaner "*/1 * * * *"
$GOMPLATE -f $TEMPLATES_DIR/production-jaeger-install.yaml.template -o ./jaeger-deployment
$GOMPLATE -f ./es-index.template -o ./es-index
cat ./jaeger-deployment ./es-index >> ./01-install.yaml
$GOMPLATE -f $TEMPLATES_DIR/production-jaeger-assert.yaml.template -o ./01-assert.yaml

# Report some spans
render_report_spans "$JAEGER_NAME" "production" 5 "00" true 02

# Enable Elasticsearch index cleaner
sed "s~enabled: false~enabled: true~gi" ./01-install.yaml > ./03-install.yaml

# Wait for the execution of the cronjob
$GOMPLATE -f $TEMPLATES_DIR/wait-for-cronjob-execution.yaml.template -o ./04-wait-es-index-cleaner.yaml

# Disable Elasticsearch index cleaner to ensure it is not run again while the test does some checks
$GOMPLATE -f ./01-install.yaml -o ./05-install.yaml

# Check if the indexes were cleaned or not
render_check_indices "00" "06" "'--pattern', 'jaeger-span-\d{4}-\d{2}-\d{2}', '--assert-count-indices', '0',"

unset JAEGER_NAME
unset CRONJOB_NAME


if [ "$SKIP_ES_EXTERNAL" = true ]; then
    skip_test "es-simple-prod" "skipping es-simple-prod test tests because SKIP_ES_EXTERNAL is true. Covered by the self_provisioned_elasticsearch_test"
else
    start_test "es-simple-prod"
    jaeger_name="simple-prod"

    # Deploy Elasticsearch
    render_install_elasticsearch "00"
    # Deploy Jaeger in production mode
    render_install_jaeger "$jaeger_name" "production" "01"
    # Run smoke test
    render_smoke_test "$jaeger_name" "production" "02"
fi


start_test "es-rollover"

export jaeger_name="my-jaeger"

# Install Elasticsearch instance
render_install_elasticsearch "00"

# Install Jaeger
render_install_jaeger "$jaeger_name" "production" "01"

# Report some spans
render_report_spans "$jaeger_name" "production" 2 "00" "true" "02"

# Check the effects in the database
render_check_indices "00" "03" "'--pattern', 'jaeger-span-\d{4}-\d{2}-\d{2}', '--assert-exist',"
render_check_indices "01" "04" "'--pattern', 'jaeger-span-\d{6}', '--assert-count-indices', '0',"

# Step 5 enables rollover. No autogenerated

# Report more spans
render_report_spans "$jaeger_name" "production" 2 "02" "true" "06"

# Check the effects in the database
render_check_indices "02" "07" "'--pattern', 'jaeger-span-\d{4}-\d{2}-\d{2}', '--assert-exist',"
render_check_indices "03" "08" "'--pattern', 'jaeger-span-\d{6}', '--assert-exist',"
render_check_indices "04" "09" "'--name', 'jaeger-span-read', '--assert-exist',"

# Report more spans
render_report_spans "$jaeger_name" "production" 2 "03" "true" "10"

# Wait for the execution of the cronjob
export CRONJOB_NAME="my-jaeger-es-rollover"
$GOMPLATE -f $TEMPLATES_DIR/wait-for-cronjob-execution.yaml.template -o ./11-wait-rollover.yaml

# Check the effects in the database
render_check_indices "05" "11" "'--name', 'jaeger-span-000002',"
render_check_indices "06" "12" "'--name', 'jaeger-span-read', '--assert-count-docs', '4', '--jaeger-service', 'smoke-test-service',"


if [ "$SKIP_ES_EXTERNAL" = true ]; then
    skip_test "es-spark-dependencies" "This test requires an insecure ElasticSearch instance"
else
    start_test "es-spark-dependencies"

    jaeger_name="my-jaeger"

    render_install_elasticsearch "00"

    # The step 1 creates the Jaeger instance

    export CRONJOB_NAME="my-jaeger-spark-dependencies"
    $GOMPLATE -f $TEMPLATES_DIR/wait-for-cronjob-execution.yaml.template -o ./02-wait-spark-job.yaml
fi
