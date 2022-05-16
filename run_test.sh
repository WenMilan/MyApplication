#!/bin/bash
set -eu -o pipefail

appfilename="app-debug.apk"
testfilename="app-debug-androidTest.apk"
devicePoolArn="arn:aws:devicefarm:us-west-2:272510231547:devicepool:34b18a67-8bad-4c40-b42e-aa96bba3cca7/b00b0350-a024-477c-9c82-0f6d6242a977"
projectArn='arn:aws:devicefarm:us-west-2:272510231547:project:34b18a67-8bad-4c40-b42e-aa96bba3cca7'
runname="MyAndroidTest $(date '+%Y-%m-%d %H:%M:%S')"

pkgfile=`find . -name ${appfilename}`
testfile=`find . -name ${testfilename}`
pkgOutput=$(aws devicefarm create-upload --project-arn ${projectArn} --name ${appfilename} --type ANDROID_APP)
pkgUploadArn=`echo ${pkgOutput}|jq -r ."upload.arn"`
#echo $pkgUploadArn
pkgUploadUrl=`echo ${pkgOutput}|jq -r ."upload.url"`
testOutput=$(aws devicefarm create-upload --project-arn ${projectArn} --name ${testfilename} --type INSTRUMENTATION_TEST_PACKAGE)
testUploadArn=`echo ${testOutput}|jq -r ."upload.arn"`
#echo $testUploadArn
testUploadUrl=`echo ${testOutput}|jq -r ."upload.url"`
echo "#start to upload $pkgfile at $(date '+%Y-%m-%d %H:%M:%S')"
curl -T ${pkgfile} ${pkgUploadUrl}
echo "#finish to upload $pkgfile at $(date '+%Y-%m-%d %H:%M:%S')"
echo "#start to upload $testfile at $(date '+%Y-%m-%d %H:%M:%S')"
curl -T ${testfile} ${testUploadUrl}
echo "#finish to upload $testfile at $(date '+%Y-%m-%d %H:%M:%S')"

#check upload finished
uploadArns=(
	"${testUploadArn}"
	"${pkgUploadArn}"
)

for uploadArn in "${uploadArns[@]}"; do
  i=0
  status=PENDING
  echo "######Start $uploadArn"
  while true ;do
    sleep 1
    status=$(aws devicefarm get-upload --arn "${uploadArn}"|jq -r ."upload.status")
    echo "#loop "$i
    echo status=$status
    if [ "$status"x = "SUCCEEDED"x ]; then
      echo "######status success"
      break
    fi

    i=`expr $i + 1`
    #20 seconds timeout
    if [ $i -gt 20 ]; then
      echo "###upload task time out"
      exit 255
    fi
  done
done

runArn=$(aws devicefarm schedule-run --project-arn "${projectArn}" --app-arn "${pkgUploadArn}" --device-pool-arn "${devicePoolArn}" --name "${runname}" --test type=INSTRUMENTATION,testPackageArn="${testUploadArn}"|jq -r ."run.arn")
echo runArn=$runArn
i=0
status=PENDING
result=FAILED
while true ;do
  sleep 60
  status=$(aws devicefarm get-run --arn "${runArn}"|jq -r ."run.status")
  echo "#loop "$i
  echo status=$status
  if [ "$status"x = "COMPLETED"x ]; then
    result=$(aws devicefarm get-run --arn "${runArn}"|jq -r ."run.result")
    if [ "$result"x = "PASSED"x ]; then
      exit 0
    else
      echo "####test cases not passed, please check the detail in device farm"
      exit 255
    fi
  fi

  i=`expr $i + 1`
  #120 minutes timeout
  if [ $i -gt 120 ]; then
    echo "###execute run task time out"
    exit 255
  fi
done

