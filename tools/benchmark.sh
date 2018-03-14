#!/bin/bash

Usage() {
  echo "Usage: bash tools/benchmark.sh model_output_dir"
}

if [ $# -lt 1 ]; then
  Usage
  exit 1
fi

CURRENT_DIR=`dirname $0`
source ${CURRENT_DIR}/env.sh

MODEL_OUTPUT_DIR=$1

if [ -f "$MODEL_OUTPUT_DIR/benchmark_model" ]; then
  rm -rf $MODEL_OUTPUT_DIR/benchmark_model
fi

if [ "$EMBED_MODEL_DATA" = 0 ]; then
  cp codegen/models/${MODEL_TAG}/${MODEL_TAG}.data $MODEL_OUTPUT_DIR
fi

if [ x"$TARGET_ABI" == x"host" ]; then
  bazel build --verbose_failures -c opt --strip always benchmark:benchmark_model \
    --copt="-std=c++11" \
    --copt="-D_GLIBCXX_USE_C99_MATH_TR1" \
    --copt="-Werror=return-type" \
    --copt="-DMACE_MODEL_TAG=${MODEL_TAG}" \
    --copt="-O3" \
    --define openmp=true \
    --define production=true || exit 1

  cp bazel-bin/benchmark/benchmark_model $MODEL_OUTPUT_DIR

  MACE_CPP_MIN_VLOG_LEVEL=$VLOG_LEVEL \
  ${MODEL_OUTPUT_DIR}/benchmark_model \
      --model_data_file=${PHONE_DATA_DIR}/${MODEL_TAG}.data \
      --device=${DEVICE_TYPE} \
      --input_node="${INPUT_NODES}" \
      --input_shape="${INPUT_SHAPES}"\
      --output_node="${OUTPUT_NODES}" \
      --output_shape="${OUTPUT_SHAPES}"\
      --input_file=${MODEL_OUTPUT_DIR}/${INPUT_FILE_NAME} || exit 1

else
  bazel build --verbose_failures -c opt --strip always benchmark:benchmark_model \
    --crosstool_top=//external:android/crosstool \
    --host_crosstool_top=@bazel_tools//tools/cpp:toolchain \
    --cpu=${TARGET_ABI} \
    --copt="-std=c++11" \
    --copt="-D_GLIBCXX_USE_C99_MATH_TR1" \
    --copt="-Werror=return-type" \
    --copt="-DMACE_MODEL_TAG=${MODEL_TAG}" \
    --copt="-O3" \
    --define openmp=true \
    --define production=true || exit 1

  cp bazel-bin/benchmark/benchmark_model $MODEL_OUTPUT_DIR

  adb shell "mkdir -p ${PHONE_DATA_DIR}" || exit 1
  IFS=',' read -r -a INPUT_NAMES <<< "${INPUT_NODES}"
  for NAME in "${INPUT_NAMES[@]}";do
    FORMATTED_NAME=$(sed s/[^[:alnum:]]/_/g <<< ${NAME})
    adb push ${MODEL_OUTPUT_DIR}/${INPUT_FILE_NAME}_${FORMATTED_NAME} ${PHONE_DATA_DIR} || exit 1
  done
  adb push ${MODEL_OUTPUT_DIR}/benchmark_model ${PHONE_DATA_DIR} || exit 1
  if [ "$EMBED_MODEL_DATA" = 0 ]; then
    adb push ${MODEL_OUTPUT_DIR}/${MODEL_TAG}.data ${PHONE_DATA_DIR} || exit 1
  fi

  adb </dev/null shell \
    LD_LIBRARY_PATH=${PHONE_DATA_DIR} \
    MACE_CPP_MIN_VLOG_LEVEL=$VLOG_LEVEL \
    MACE_RUN_PARAMETER_PATH=${PHONE_DATA_DIR}/mace_run.config \
    MACE_LIMIT_OPENCL_KERNEL_TIME=${LIMIT_OPENCL_KERNEL_TIME} \
    MACE_OPENCL_PROFILING=1 \
    ${PHONE_DATA_DIR}/benchmark_model \
    --model_data_file=${PHONE_DATA_DIR}/${MODEL_TAG}.data \
    --device=${DEVICE_TYPE} \
    --input_node="${INPUT_NODES}" \
    --input_shape="${INPUT_SHAPES}"\
    --output_node="${OUTPUT_NODES}" \
    --output_shape="${OUTPUT_SHAPES}"\
    --input_file=${PHONE_DATA_DIR}/${INPUT_FILE_NAME} || exit 1
fi
