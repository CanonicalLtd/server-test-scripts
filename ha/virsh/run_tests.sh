#!/bin/bash

# shellcheck disable=SC1091
source /etc/profile.d/libvirt-uri.sh

./delete-cluster.sh || exit 1

test_failed=0
for file in tests/*_test.sh; do
  ./setup-cluster.sh
  if ! bash "$file"; then
    test_failed=1
  fi
  ./delete-cluster.sh
done

if [ $test_failed -eq 1 ]; then
  echo -e "\033[0;31mThere are failing tests\033[0m"
  exit 3
fi

echo -e "\033[0;32mAll tests successfully passed!\033[0m"
