import time
import pandas as pd
import psutil
from threading import Lock
import threading


class Monitor():
    def __init__(self,
                 sample_interval: int = 1,
                 csv_file: str = 'monitor.csv',
                 save_interval: int = 10
                 ):
        self.sample_interval = sample_interval
        self.data = pd.DataFrame(
            columns=['time', 'cpu', 'memory', 'disk', 'rows_written'])
        self.last_save = time.time()
        self.csv_file = csv_file
        self.save_interval = save_interval
        self.lock = Lock()  # Add lock for thread safety
        self._stop = False

    def _sample(self):
        current_time = time.time()
        new_row = pd.DataFrame({
            'time': [pd.Timestamp.fromtimestamp(current_time)],
            'cpu': [psutil.cpu_percent()],
            'memory': [psutil.virtual_memory().used],
            'disk': [psutil.disk_usage('/root/workspace/TDinternal/sim/dnode1/').used],
            'rows_written': [0]
        })

        with self.lock:  # Use lock when modifying DataFrame
            self.data = pd.concat(
                [self.data if not self.data.empty else None, new_row], ignore_index=True)

        # print(self.data)

        # Save data when reaching save interval
        if current_time - self.last_save >= self.save_interval:
            self.data.to_csv(self.csv_file, index=False)
            self.last_save = current_time

    def run(self):
        while True:
            # Check if stop signal is received
            with self.lock:
                if self._stop:
                    break

            # Sample data
            self._sample()

            # Sleep for sample interval
            time.sleep(self.sample_interval)

    def fetch(self, time_range=None):
        """
        Fetch data from monitor
        """
        with self.lock:
            if time_range is None:
                return self.data.copy()
            else:
                start_time, end_time = time_range
                return self.data[(self.data['time'] >= start_time) & (self.data['time'] <= end_time)].copy()

    def stop(self):
        with self.lock:
            self._stop = True


if __name__ == '__main__':
    monitor = Monitor(
        sample_interval=1,
        csv_file='monitor.csv',
        save_interval=10
    )

    monitor_thread = threading.Thread(target=monitor.run)
    monitor_thread.start()

    while True:
        cmd = input("Enter 'exit' to stop monitoring: ")
        if cmd == 'exit':
            monitor.stop()
            break

    monitor_thread.join()  # Wait for the thread to exit
