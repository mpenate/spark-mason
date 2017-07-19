#!/bin/bash -e

while getopts "chdtp:" OPTION
do
   case $OPTION in
    c) 
		CLEAN=true
		;;
    h)
		HISTORY_SERVER_IMAGE=true	
		;;
	
	d)
		DISPATCHER_IMAGE=true
		;;
	t)
		SPARK_TESTS=true
		;;
	p)
		PUSH_REGISTRY=true
		REG=$OPTARG
		;;
	\?)
		cat << EOM
By default this script only performs mvn test-compile (with scalastyle) and mvn clean package (skipping all test cases), you can add the following flags to extend its behaviour:
-t	run spark test suite
-h	generates history server docker image
-d	generates dispatcher docker image
-t	run a local registry publishing generated spark docker images on it
EOM
		exit
		;;
	esac
done

if [ $CLEAN ]; then
	mvn clean -q
fi

#Multiplexing
echo "Packaging spark"
export R_HOME=/usr/lib/R

mvn -T6 package -DskipTests -DskipITs -DskipUTs 


if [ $SPARK_TESTS ]; then
	mvn -T6 test
fi

if [ $DISPATCHER_IMAGE ]; then
	echo "Building dispatcher image..."
	docker build -f DockerfileDispatcher -t ${REG:=localhost}/stratio-spark-"${USER}":test .
fi

if [ $HISTORY_SERVER_IMAGE ]; then
	echo "Building history server image..."
	docker build -f DockerfileHistory -t ${REG:=localhost}/stratio-spark-hs-"${USER}":test .
fi

if [ $PUSH_REGISTRY ]; then

	echo "Pushing images to registry at ${REG}..."
fi
if [ $HISTORY_SERVER_IMAGE ]; then	
		docker push ${REG}/stratio-spark-hs-"${USER}":test
fi
if [ $DISPATCHER_IMAGE ]; then
		docker push ${REG}/stratio-spark-"${USER}":test
fi

