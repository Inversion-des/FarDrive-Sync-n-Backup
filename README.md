# FarDrive Sync&Backup
A small but powerful sync/backup tool.
> ⚠ Right now the project is in the early proof of concept stage. Works only on Windows with limited functionality.

## How to test a simple backup/restore scenario:

1. Ensure you are on Windows.
1. Download and unpack [the latest release](https://github.com/Inversion-des/FarDrive-Sync-n-Backup/releases) (8 MB) or clone the repo.
1. In the `app` dir, copy `app_sample.rb` and rename to `app.rb`.
1. Edit `app.rb`:  
Define `@local_1`, `@local_2` and `@storages`.  
The simples storage config looks like: 
```
@storages = {
	LocalFS: {
		dir_path: 'F:/FarDrive_storage'
	}
}
```
5. Now in the main dir you can run cmd and do `run -up` and `run -down`. Special `.db` dir will be added to the backup dir (`@local_1`).


## I need more
Read other samples with comments in that file.

For example, if you want to exclude some dirs, look for the `-update_filter` command.  
Replace those `set_rule` lines with something like this: 
```
sync.filter.set_rule(
	dir_paths: ['app/logs', 'build/cache'],
	subdirs: true,
	exclude_files: '*'
) 
```
And then use `run -update_filter` once to save the filter for the current backup.


## Community
If you have any questions/feedback — welcome to [Discussions](https://github.com/Inversion-des/FarDrive-Sync-n-Backup/discussions) and our [Subreddit](https://www.reddit.com/r/FarDrive_SyncBackup/).  
Any issues — welcome to [Issues](https://github.com/Inversion-des/FarDrive-Sync-n-Backup/issues).
