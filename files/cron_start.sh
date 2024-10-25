#!/bin/bash

CronCommand="/bin/bash /opt/y.sh"




################################# do not edit if confused ########################################
env >/opt/env
if [ "$PUID" != "$PGID" ]; then
  groupadd -g $PGID
  useradd --no-create-home --no-log-init -Uu $PUID --password $RANDOM dockercronjobworker
else
  useradd --no-create-home --no-log-init -Uu $PUID --password $RANDOM dockercronjobworker
fi
echo "$CronSchedule sudo -E --group=dockercronjobworker --user=dockercronjobworker $CronCommand >/opt/cron.log 2>/opt/cron.log" >/opt/cron
crontab /opt/cron
touch /opt/cron.log
cron && tail -f /opt/cron.log
