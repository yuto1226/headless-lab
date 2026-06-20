# Exercise Master Seed Data

`exercise_master_seed.csv` contains 10 beginner-oriented bodyweight exercises for `ExerciseMaster__c`.

Import the records into the configured default org:

```sh
sf data import bulk --sobject ExerciseMaster__c --file data/exercise_master_seed.csv --wait 10
```

To select an org explicitly:

```sh
sf data import bulk --target-org headless-lab --sobject ExerciseMaster__c --file data/exercise_master_seed.csv --wait 10
```

This command inserts records. Running it more than once creates duplicates because `ExerciseMaster__c` does not currently have an external ID for upsert.
