#!/bin/bash

./setup-cluster.sh

test_failed=0
for file in tests/*_test.sh; do
  bash $file
  if [ $? != 0 ]; then
    test_failed=1
  fi
done

./delete-cluster.sh

if [ $test_failed -eq 1 ]; then
  exit 3
fi