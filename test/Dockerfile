FROM ubuntu:latest
RUN apt update && apt install -y python3 python3-pip sudo wget
RUN wget https://raw.githubusercontent.com/gdraheim/docker-systemctl-replacement/master/files/docker/systemctl3.py -O /usr/local/bin/systemctl
RUN chmod +x /usr/local/bin/systemctl
CMD tail --follow /dev/null