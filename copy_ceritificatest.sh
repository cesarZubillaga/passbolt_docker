sudo apt install libnss3-tools mkcert -y
mkcert passbolt.local '*.passbolt.local' passbolt.local localhost 127.0.0.1 ::1
sudo apt-get install ca-certificates
sudo cp -Rf ./passbolt* /etc/ssl/certificates
mkcert -install
docker cp /etc/ssl/certs/passbolt.local+5-key.pem docker-compose_passbolt_1:/etc/ssl/certs/certificate.key
docker cp /etc/ssl/certs/passbolt.local+5.pem docker-compose_passbolt_1:/etc/ssl/certs/certificate.crt
docker exec docker-compose_passbolt_1 service nginx reload
