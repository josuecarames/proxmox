In order to schedule this script, run in the host machine: 

`sudo crontab -e`

Then, type the following line and save:

`*/2 * * * * /root/status.sh > /root/status.log 2>&1`

This will schedule the script to run every two minutes and create a log file in the directory shown. 

Make sure to run the following command for the script to be executable: 

`chmod +x /root/status.sh`