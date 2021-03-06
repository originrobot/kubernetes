#!/bin/bash

# Copyright 2014 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -o errexit
set -o nounset
set -o pipefail

KUBE_ROOT=$(dirname "${BASH_SOURCE}")/..
source "${KUBE_ROOT}/hack/lib/init.sh"

kube::golang::setup_env

BUILD_TARGETS=(
  vendor/k8s.io/kube-gen/cmd/client-gen
  vendor/k8s.io/kube-gen/cmd/lister-gen
  vendor/k8s.io/kube-gen/cmd/informer-gen
)
make -C "${KUBE_ROOT}" WHAT="${BUILD_TARGETS[*]}"

clientgen=$(kube::util::find-binary "client-gen")
listergen=$(kube::util::find-binary "lister-gen")
informergen=$(kube::util::find-binary "informer-gen")

# Please do not add any logic to this shell script. Add logic to the go code
# that generates the set-gen program.
#

GROUP_VERSIONS=(${KUBE_AVAILABLE_GROUP_VERSIONS})
GV_DIRS=()
for gv in "${GROUP_VERSIONS[@]}"; do
	# add items, but strip off any leading apis/ you find to match command expectations
	api_dir=$(kube::util::group-version-to-pkg-path "${gv}")
	nopkg_dir=${api_dir#pkg/}
	nopkg_dir=${nopkg_dir#vendor/k8s.io/api/}
	pkg_dir=${nopkg_dir#apis/}

	# skip groups that aren't being served, clients for these don't matter
    if [[ " ${KUBE_NONSERVER_GROUP_VERSIONS} " == *" ${gv} "* ]]; then
      continue
    fi

	GV_DIRS+=("${pkg_dir}")
done
# delimit by commas for the command
GV_DIRS_CSV=$(IFS=',';echo "${GV_DIRS[*]// /,}";IFS=$)

# This can be called with one flag, --verify-only, so it works for both the
# update- and verify- scripts.
${clientgen} "$@"
${clientgen} -t "$@" --output-base "${KUBE_ROOT}/vendor"
${clientgen} --clientset-name="clientset" --input-base="k8s.io/kubernetes/vendor/k8s.io/api" --input="${GV_DIRS_CSV}" "$@"
# Clientgen for federation clientset.
${clientgen} --clientset-name=federation_internalclientset --clientset-path=k8s.io/kubernetes/federation/client/clientset_generated --input="../../federation/apis/federation/","api/","extensions/","batch/","autoscaling/" --included-types-overrides="api/Service,api/Namespace,extensions/ReplicaSet,api/Secret,extensions/Ingress,extensions/Deployment,extensions/DaemonSet,api/ConfigMap,api/Event,batch/Job,autoscaling/HorizontalPodAutoscaler"   "$@"
${clientgen} --clientset-name=federation_clientset --clientset-path=k8s.io/kubernetes/federation/client/clientset_generated --input-base="k8s.io/kubernetes/vendor/k8s.io/api" --input="../../../federation/apis/federation/v1beta1","core/v1","extensions/v1beta1","batch/v1","autoscaling/v1" --included-types-overrides="core/v1/Service,core/v1/Namespace,extensions/v1beta1/ReplicaSet,core/v1/Secret,extensions/v1beta1/Ingress,extensions/v1beta1/Deployment,extensions/v1beta1/DaemonSet,core/v1/ConfigMap,core/v1/Event,batch/v1/Job,autoscaling/v1/HorizontalPodAutoscaler"   "$@"

listergen_kubernetes_apis=(
pkg/api
$(
  cd ${KUBE_ROOT}
  # because client-gen doesn't do policy/v1alpha1, we have to skip it too
  find pkg/apis -name types.go | xargs -n1 dirname | sort | grep -v pkg.apis.policy.v1alpha1
)
)
listergen_kubernetes_apis=(${listergen_kubernetes_apis[@]/#/k8s.io/kubernetes/})
listergen_staging_apis=(
$(
  cd ${KUBE_ROOT}/staging/src
  # because client-gen doesn't do policy/v1alpha1, we have to skip it too
  find k8s.io/api -name types.go | xargs -n1 dirname | sort | grep -v pkg.apis.policy.v1alpha1
)
)

LISTERGEN_APIS=$(IFS=,; echo "${listergen_kubernetes_apis[*]}")
LISTERGEN_APIS+=","
LISTERGEN_APIS+=$(IFS=,; echo "${listergen_staging_apis[*]}")
${listergen} --input-dirs "${LISTERGEN_APIS}" "$@"

informergen_kubernetes_apis=(
pkg/api
$(
  cd ${KUBE_ROOT}
  # because client-gen doesn't do policy/v1alpha1, we have to skip it too
  find pkg/apis -name types.go | xargs -n1 dirname | sort | grep -v pkg.apis.policy.v1alpha1
)
)
informergen_kubernetes_apis=(${informergen_kubernetes_apis[@]/#/k8s.io/kubernetes/})
informergen_staging_apis=(
$(
  cd ${KUBE_ROOT}/staging/src
  # because client-gen doesn't do policy/v1alpha1, we have to skip it too
  find k8s.io/api -name types.go | xargs -n1 dirname | sort | grep -v pkg.apis.policy.v1alpha1
)
)


INFORMERGEN_APIS=$(IFS=,; echo "${informergen_kubernetes_apis[*]}")
INFORMERGEN_APIS+=","
INFORMERGEN_APIS+=$(IFS=,; echo "${informergen_staging_apis[*]}")

${informergen} \
  --input-dirs "${INFORMERGEN_APIS}" \
  --versioned-clientset-package k8s.io/kubernetes/pkg/client/clientset_generated/clientset \
  --internal-clientset-package k8s.io/kubernetes/pkg/client/clientset_generated/internalclientset \
  --listers-package k8s.io/kubernetes/pkg/client/listers \
  "$@"


# You may add additional calls of code generators like set-gen above.

# call generation on sub-project for now
KUBEGEN_PKG=./vendor/k8s.io/kube-gen vendor/k8s.io/kube-aggregator/hack/update-codegen.sh
KUBEGEN_PKG=./vendor/k8s.io/kube-gen vendor/k8s.io/sample-apiserver/hack/update-codegen.sh
KUBEGEN_PKG=./vendor/k8s.io/kube-gen vendor/k8s.io/apiextensions-apiserver/hack/update-codegen.sh
KUBEGEN_PKG=./vendor/k8s.io/kube-gen vendor/k8s.io/metrics/hack/update-codegen.sh
