```bash
for i in {1..10}; 
do 
    cd ${PRJ_PATH}/community/tests/army && ./pytest.sh python3 ./test.py -f cluster/snapshot.py -N 3 -L 3 -D 2
done
```