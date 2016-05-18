# eec_akm
Energy Efficiency Project Scripts
Usage - #./akm_dvfs -[r/c/m/h] -t sample_rate -f logfile(r mode only) -s sleep duration(m mode only)

Options are

-r   Record mode - Generates utilization averages for workload duration. Dumped to log file

-f   Specify different log file for record mode

-c  Capture mode - Capture utilization and operating frequencies. Dumped to lookup file

-m Monitor mode - Monitor workload utilizations and change operating frequencies dynamically. Needs root shell

-s  Sleep duration of script for monitor mode

-t   Duration for sampling\(used by top\) the utilization. Default is 3s

-h  Show this help

Press q to exit any mode.
