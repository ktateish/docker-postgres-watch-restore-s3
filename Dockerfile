FROM schickling/postgres-restore-s3

ENV POSTGRES_MASTER_USER **None**
ENV POSTGRES_MASTER_PASSWORD **None**
ENV MAX_RETRY 5
ENV INTERVAL 60
ENV RELATION_CHECK_SQL **None**

ADD watch.sh watch.sh
ADD restore.sh restore.sh
ADD relation_check relation_check

CMD ["sh", "watch.sh"]
