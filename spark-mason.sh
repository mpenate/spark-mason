#!/bin/bash -xe

while getopts "chdtp" OPTION
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
		LOCAL_REGISTRY=true
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
mvn -T6 package -DskipTests -DskipITs -DskipUTs 


if [ $SPARK_TESTS ]; then
	mvn -T6 test
fi

if [ $DISPATCHER_IMAGE ]; then
	echo "Building dispatcher image..."
	docker build -f DockerfileDispatcher -t localhost/stratio-spark-"${USER}":test .
fi

if [ $HISTORY_SERVER_IMAGE ]; then
	echo "Building history server image..."
	docker build -f DockerfileHistory -t localhost/stratio-spark-hs-"${USER}":test .
fi

if [ $LOCAL_REGISTRY ]; then
	echo "Generaing self signed certificate"
	DOMAIN=$(hostname -f)
	HOSTNAME=$(hostname -f)

	CERTPATH="/tmp/localregistrycerts"
	mkdir -p ${CERTPATH}
	echo "[ req ]
	distinguished_name = req_distinguished_name
	prompt = no
	[ req_distinguished_name ]
	C                      = US
	ST                     = CA
	L                      = SF
	O                      = stratio
	OU                     = stratio
	CN                     =${DOMAIN}
	emailAddress           = selfsign@invented.com " > ${CERTPATH}crt.conf

	openssl genrsa -out ${CERTPATH}ca.key 1024
	openssl req -config ${CERTPATH}crt.conf -new -key ${CERTPATH}ca.key -out ${CERTPATH}ca.csr
	openssl x509 -req -days 1024 -in ${CERTPATH}ca.csr -signkey ${CERTPATH}ca.key -out ${CERTPATH}ca.crt

	openssl genrsa -out ${CERTPATH}registry.key 1024
	openssl req -new  -config ${CERTPATH}crt.conf -key ${CERTPATH}registry.key -out ${CERTPATH}registry.csr
	openssl x509 -req -days 1024 -CAcreateserial -CAserial ${CERTPATH}ca.seq -in ${CERTPATH}registry.csr -CA ${CERTPATH}ca.crt -CAkey ${CERTPATH}ca.key -out ${CERTPATH}registry.crt

	cat ${CERTPATH}registry.crt ${CERTPATH}ca.crt > ${CERTPATH}cert-chain.pem

	echo "Running docker registry local server on host port 5000..."
	docker stop registry
	docker rm registry
	docker run -d \
  	--name registry \
  	-v /tmp/localregistrycerts:/certs \
 	-e REGISTRY_HTTP_ADDR=0.0.0.0:5000 \
 	-e REGISTRY_HTTP_TLS_CERTIFICATE=/certs/registry.crt \
  	-e REGISTRY_HTTP_TLS_KEY=/certs/registry.key \
 	-p 5000:5000 \
  	registry:2
	echo "Pushing images to local registry..."
fi
if [ $HISTORY_SERVER_IMAGE ]; then	
		docker push localhost:5000/stratio-spark-hs-"${USER}":test
fi
if [ $DISPATCHER_IMAGE ]; then
		docker push localhost:5000/stratio-spark-"${USER}":test
fi

