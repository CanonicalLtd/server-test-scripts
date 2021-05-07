# shellcheck shell=dash

# shellcheck disable=SC1090
. "$(dirname "$0")/helper/test_helper.sh"
. "$(dirname "$0")/helper/common_vars.sh"

# cheat sheet:
#  assertTrue $?
#  assertEquals ["explanation"] 1 2
#  oneTimeSetUp()
#  oneTimeTearDown()
#  setUp() - run before each test
#  tearDown() - run after each test

# Where the "utils" repository will be temporarily cloned.
UTILSDIR=""
# Which tags to test.
TAGS_REGEX='\(latest\|beta\|edge\)'

oneTimeSetUp()
{
    UTILSDIR=$(mktemp -d)

    if [ -z "${UTILSDIR}" ]; then
        echo "E: Could not create temporary directory.  Aborting." > /dev/stderr
        exit 1
    fi

    UTILSDIR="${UTILSDIR}/utils"

    if ! git clone -q --depth 1 https://git.launchpad.net/~canonical-server/ubuntu-docker-images/+git/utils "${UTILSDIR}"; then
        echo "E: Failed to clone 'utils' repository.  Aborting." > /dev/stderr
        exit 1
    fi
}

oneTimeTearDown()
{
    rm -rf "${UTILSDIR}"
}

# Standalone checks that will be performed for each image.

# Check that all supported architectures are present in the manifest
# list for every image.
test_all_supported_architectures_are_available()
{
    # We only support querying AWS for now.
    local registries="aws"
    local listed_architectures
    local images_list
    # Which tags to test.
    local tags_regex='\(latest\|beta\|edge\)'
    local ret=0

    debug "Checking if all supported architectures are present in the manifest list of each image"

    # Iterate over the available registries...
    for registry in ${registries}; do
        # ... and over the available namespaces...
        for namespace in ${SUPPORTED_NAMESPACES}; do
            # ... and over the list of all images for the
            # registry/namespace combination...
            images_list=$("${UTILSDIR}"/list-all-images.sh \
                                       --registry "${registry}" \
                                       --namespace "${namespace}")
            if [ "${DOCKER_PACKAGE}" != "$(basename "$0" | sed 's@\(.*\)_test\.sh@\1@')" ]; then
                # If the user has specified an image name to be tested, then
                # we just test it.
                if ! images_list=$(echo "${images_list}" | grep -Fw "${DOCKER_PACKAGE}"); then
                    continue
                fi
            fi
            for image in ${images_list}; do
                # ... and over the list of all available tags for each
                # image...
                for tag in $("${UTILSDIR}"/list-tags-for-image.sh \
                                          --registry "${registry}" \
                                          --namespace "${namespace}" \
                                          --image "${image}" \
                                 | grep "${tags_regex}"); do
                    debug "Checking manifest list for ${namespace}/${image}:${tag} on ${registry}"
                    # Obtain the manifest list for the current tag,
                    # and filter out everything but the published
                    # architectures.
                    listed_architectures=$("${UTILSDIR}"/list-manifest-for-image-and-tag.sh \
					                --registry "${registry}" \
					                --namespace "${namespace}" \
					                --image "${image}" \
					                --tag "${tag}" \
			                       | jq -r '.manifests[].platform.architecture')
                    if [ -z "${listed_architectures}" ]; then
                        # Check if we've gotten a valid output from
                        # the commands above.  Albeit rare, it is
                        # possible that the manifest list comes out empty.
                        echo "E: Could not obtain manifest list for ${namespace}/${image}:${tag} on ${registry}" > /dev/stderr
                        ret=1
                        continue
                    fi
                    for arch in ${SUPPORTED_ARCHITECTURES}; do
	                if ! echo "${listed_architectures}" | grep -Fwq "${arch}"; then
	                    echo "E: architecture '${arch}' not found in the manifest list of ${namespace}/${image}:${tag} on ${registry}" > /dev/stderr
	                    ret=1
	                else
                            debug "architecture '${arch}' successfully found in the manifest list of ${namespace}/${image}:${tag} on ${registry}"
                        fi
                    done
                done
            done
        done
    done

    assertTrue "Not all supported architectures are available" "$ret"
}

test_images_hashes_are_equal()
{
    # We currently support only the "ubuntu" namespace, because it's
    # the only one that is published on both registries.
    local namespaces="ubuntu"
    local images_list
    local ret=0

    if [ -z "${DOCKER_USERNAME}" ] || [ -z "${DOCKER_PASSWORD}" ]; then
        echo "E: You must specify the DOCKER_USERNAME and DOCKER_PASSWORD environment variables." > /dev/stderr
        exit 1
    fi
    export DOCKER_USERNAME DOCKER_REGISTRY

    for namespace in ${namespaces}; do
        # Verify that all supported registries have the same list of
        # images available.
        local images_list

        images_list=""
        for registry in ${SUPPORTED_REGISTRIES}; do
            if [ -z "${images_list}" ]; then
                images_list=$("${UTILSDIR}"/list-all-images.sh \
                                           --registry "${registry}" \
                                           --namespace "${namespace}" | grep -Fvw ubuntu | sort)
            else
                if [ "${images_list}" != "$("${UTILSDIR}"/list-all-images.sh \
                                                         --registry "${registry}" \
                                                         --namespace "${namespace}" | grep -Fvw ubuntu | sort)" ]; then
                    echo "E: Registry '${registry}' differs in the list of available images. Aborting." > /dev/stderr
                    return
                fi
            fi
        done

        if [ "${DOCKER_PACKAGE}" != "$(basename "$0" | sed 's@\(.*\)_test\.sh@\1@')" ]; then
            # If the user has specified an image name to be tested, then
            # we just test it.
            if ! images_list=$(echo "${images_list}" | grep -Fw "${DOCKER_PACKAGE}"); then
                continue
            fi
        fi
        for image in ${images_list}; do
            # Verify that all registries have the same set of tags for
            # this image.
            local tags_list

            tags_list=""
            for registry in ${SUPPORTED_REGISTRIES}; do
                if [ -z "${tags_list}" ]; then
                    tags_list=$("${UTILSDIR}"/list-tags-for-image.sh \
                                             --registry "${registry}" \
                                             --namespace "${namespace}" \
                                             --image "${image}" \
                                    | grep "${TAGS_REGEX}" | sort)
                else
                    if [ "${tags_list}" != "$("${UTILSDIR}"/list-tags-for-image.sh \
                                                           --registry "${registry}" \
                                                           --namespace "${namespace}" \
                                                           --image "${image}" | grep "${TAGS_REGEX}" | sort)" ]; then
                        echo "E: Registry '${registry}' differs in the list of tags for '${image}'. Aborting." > /dev/stderr
                        return
                    fi
                fi
            done

            for tag in ${tags_list}; do
                local all_digests_dir
                local got_all_registries=1

                all_digests_dir=$(mktemp -d)
                trap 'rm -rf ${all_digests_dir}' 0 INT QUIT ABRT PIPE TERM

                for registry in ${SUPPORTED_REGISTRIES}; do
                    local manifest_list

                    # The idea is to:
                    #
                    # - Create a file inside ${all_digests_dir} named
                    #   "${image}-${tag}-${arch}" which will contain
                    #   the list of all digests (from all registries)
                    #   for the specific image/tag/arch combination.
                    #
                    # - Then, verify that all digests inside this
                    #   specific file are the same.
                    if ! manifest_list=$("${UTILSDIR}"/list-manifest-for-image-and-tag.sh \
                                                      --registry "${registry}" \
                                                      --namespace "${namespace}" \
                                                      --image "${image}" \
                                                      --tag "${tag}"); then
                        echo "E: Could not obtain manifest list for ${registry} image ${namespace}/${image}:${tag}" > /dev/stderr
                        ret=1
                        got_all_registries=0
                        break
                    fi

                    if [ -z "${manifest_list}" ]; then
                        echo "E: Could not obtain manifest list for ${registry} image ${namespace}/${image}:${tag}" > /dev/stderr
                        ret=1
                        got_all_registries=0
                        break
                    fi

                    for arch in ${SUPPORTED_ARCHITECTURES}; do
                        if ! echo "${manifest_list}" \
                                | jq -er ".manifests[] | select(.platform.architecture == \"${arch}\") | .digest" >> "${all_digests_dir}/${image}-${tag}-${arch}"; then
                            echo "E: Could not obtain digest from manifest list for ${registry} image ${namespace}/${image}:${tag} (${arch})" > /dev/stderr
                            ret=1
                        fi
                    done
                done

                if [ "${got_all_registries}" -eq 1 ]; then
                    for arch in ${SUPPORTED_ARCHITECTURES}; do
                        if [ ! -f "${all_digests_dir}/${image}-${tag}-${arch}" ]; then
                            ret=1
                            continue
                        fi

                        local num_lines
                        num_lines=$(wc -l "${all_digests_dir}/${image}-${tag}-${arch}" | cut -d' ' -f1)

                        if [ "${num_lines}" -ne "$(echo "${SUPPORTED_REGISTRIES}" | wc -w)" ]; then
                            ret=1
                        elif [ "${num_lines}" -gt 0 ] \
                                 && ! uniq "${all_digests_dir}/${image}-${tag}-${arch}" | [ "$(wc -l)" -eq 1 ]; then
                            echo "E: Digests differ between registries for image ${namespace}/${image}:${tag} (${arch})" > /dev/stderr
                            echo "E: Here are the listed digests in this order: ${SUPPORTED_REGISTRIES}" > /dev/stderr
                            echo > /dev/stderr
                            sed 's/^/> /' "${all_digests_dir}/${image}-${tag}-${arch}" > /dev/stderr
                            echo > /dev/stderr
                            ret=1
                        fi
                    done
                fi

                rm -rf "${all_digests_dir}"
            done
        done
    done

    assertTrue "Not all hashes are equal" "$ret"
}

load_shunit2
