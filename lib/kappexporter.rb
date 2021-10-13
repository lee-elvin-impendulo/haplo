# frozen_string_literal: true

# Haplo Platform                                    https://haplo.org
# (c) Haplo Services Ltd 2006 - 2020            https://www.haplo.com
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.



class KAppExporter
  include KConstants

  def self.export(app_id, filename_base, options)
    KApp.in_application(app_id) do
      self.do_export(filename_base, options.split(/,/))
    end
  end

  def self.do_export(filename_base, options)
    raise 'No export filename specified' unless filename_base != nil && filename_base.length > 0

    # Get the remote console process for running commands so main server process doesn't have to fork
    remote_process = Console.remote_console_client

    # ---------------------------------------------------------------------------------------------

    files_export = true
    if options.include?('nofiles')
      files_export = false
      puts "Application files will not be exported."
    end

    erase_history = false
    if options.include?('nohistory')
      erase_history = true
      puts "API keys, Audit trail, Keychain credentials, and Object store history will not be exported"
      puts "Uploaded filenames, user names and emails, and group names and emails will be permanently anonymised before export"
    end

    # ---------------------------------------------------------------------------------------------

    # Basic details of the app are stored in a JSON file
    data = Hash.new

    data["haploExportedApplication"] = 0

    app_id = KApp.current_application
    data["applicationId"] = app_id

    hostnames = Array.new
    data["hostnames"] = hostnames
    KApp.with_pg_database do |pg|
      s = pg.exec("SELECT hostname FROM public.applications WHERE application_id=#{app_id}")
      s.each do |row|
        hostnames << row.first
      end
    end

    data["serverClassificationTags"] = KInstallProperties.server_classification_tags
    data["configurationData"] = JSON.parse(KApp.global(:javascript_config_data) || '{}')
    if erase_history
      data["configurationData"] = '{}'
    end

    File.open("#{filename_base}.json",'w') do |file|
      file.write JSON.pretty_generate(data)
    end

    # ---------------------------------------------------------------------------------------------

    # Dump the application's schema from the database
    if erase_history
      # remove original filenames
      remote_process.remote_system "psql -d #{KFRAMEWORK_DATABASE_NAME} -c \"UPDATE a#{app_id}.stored_files SET upload_filename = 'anonymous.file';\""
      # anonymise users
      remote_process.remote_system "psql -d #{KFRAMEWORK_DATABASE_NAME} -c \"UPDATE a#{app_id}.users SET name = CONCAT('Anonymous User ', id), name_first = 'Anonymous', name_last = CONCAT('User ', id), email = CONCAT('user', id, '@example.com') WHERE kind IN (0,8,16) AND password IS NOT NULL;\""
      # anonymise groups
      remote_process.remote_system "psql -d #{KFRAMEWORK_DATABASE_NAME} -c \"UPDATE a#{app_id}.users SET name = CONCAT('Anonymous Group ', id), email = CASE WHEN email IS NULL THEN NULL ELSE CONCAT('group',id,'@example.com') END WHERE KIND IN (1,17);\""
      # anonymise plugin data and system config
      remote_process.remote_system "psql -d #{KFRAMEWORK_DATABASE_NAME} -c \"UPDATE a#{app_id}.app_globals SET value_string = '{}' WHERE key = 'javascript_config_data' OR key like '_pjson_%';\""
    end
    dump_cmd = "pg_dump --schema=a#{app_id} "
    if erase_history
      # exclude API keys, Audit trail, Keychain credentials, Object store history...
      dump_cmd = "#{dump_cmd}--exclude-table-data=*.api_keys --exclude-table-data=*.audit_entries --exclude-table-data=*.keychain_credentials --exclude-table-data=*.os_objects_old "
    end
    dump_cmd = "#{dump_cmd}--no-owner #{KFRAMEWORK_DATABASE_NAME} | gzip -9 - > #{filename_base}.sql.gz"
    remote_process.remote_system dump_cmd

    # ---------------------------------------------------------------------------------------------

    # Tar up the files
    tgz_file = "#{File.expand_path(filename_base)}.tgz"
    if files_export
      remote_process.remote_system "cd #{StoredFile.disk_root}; tar cf - . | gzip -9 - > #{tgz_file}"
    else
      # Make an empty .tgz file to make import easier
      empty_dirname = "/tmp/k_export_blank_dir_#{Process.pid}_#{Thread.current.__id__}"
      FileUtils.mkdir(empty_dirname)
      remote_process.remote_system "cd #{empty_dirname}; tar cf - . | gzip - > #{tgz_file}"
      FileUtils.rmdir(empty_dirname)
    end
  end

end

