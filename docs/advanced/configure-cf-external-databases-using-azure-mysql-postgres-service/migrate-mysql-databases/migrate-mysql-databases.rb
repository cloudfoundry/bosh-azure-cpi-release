# Migrate MySQL database from one host to another one
# This script is only tested on Cloud Foundry
#
# Prerequisites:
#   1. ruby and gems
#     ```
#     sudo apt-get install ruby
#     sudo gem install logging
#     ```
#   2. mysql client (mysql, mysqldump)
#     ```
#     sudo apt-get install mysql-client
#     ```
#   3. manifest
#     A manifest to configure the migration source and destination. See example at `manifest-example.yml`
#     Edit the manifest, and add dbname, credential, host, related information for your environment.
# 
# Usage:
#   ```
#   ruby migrate-mysql-databases.rb manifest-example.yml
#   ```

require 'fileutils'
require 'json'
require 'logging'
require 'open3'
require 'ostruct'
require 'securerandom'
require 'yaml'

$logger = Logging.logger(STDOUT)
$logger.level = :info

class SysCmd
  def self.exec(cmd)
    stdout, stderr, status = Open3.capture3(cmd)
    raise "Failed to execute #{cmd}.\n  Output:  #{stdout}\n  Error:  #{stderr}" if status != 0
    stdout
  end
end

class Database
  attr_reader :host, :dbname

  def initialize(host, dbname, username, password, port) #TODO: ssl
    @host = host
    @port = port
    @username = username
    @password = password
    @dbname = dbname
    validate
  end

  def db_exist?
    begin
      cmd = cmd_prefix + %{--execute='?' #{@dbname}}
      SysCmd.exec(cmd)
    rescue
      return false
    end
    true
  end

  # Export the database to a local file
  # @return backup_file
  def export
    backup_file_folder = 'backup_files'
    FileUtils.mkdir_p(backup_file_folder)
    backup_file = "#{backup_file_folder}/#{@dbname}.sql"
    cmd = mysqldump_cmd_prefix + %{--single-transaction #{@dbname} > #{backup_file}}
    $logger.debug("Executing: #{cmd}")
    SysCmd.exec(cmd)
    backup_file
  end

  # Import the database from a local file
  def import(backup_file)
    #raise "#{backup_file} does not exist!" unless File.exist?(backup_file)

    create_db unless db_exist?

    cmd = cmd_prefix + %{#{@dbname} < #{backup_file}}
    $logger.debug("Executing: #{cmd}")
    SysCmd.exec(cmd)
  end

  private

  def cmd_prefix
      %{mysql --host='#{@host}' --user='#{@username}' --password='#{@password}' --port=#{@port} }
  end

  def mysqldump_cmd_prefix
      %{mysqldump --host='#{@host}' --user='#{@username}' --password='#{@password}' --port=#{@port} }
  end

  def validate
    cmd = cmd_prefix + %{--execute='?'}
    SysCmd.exec(cmd)
  end

  # should only be called in import()
  def create_db
    cmd = cmd_prefix + %{--execute='create database `#{@dbname}`'}
    $logger.debug("Executing: #{cmd}")
    SysCmd.exec(cmd)
  end
end

class Migrator
  def initialize(src, dest)
    @src = src
    @dest = dest
  end

  def exec_migration
    $logger.info("Migrating #{@src.dbname}")
    backup_file = @src.export
    @dest.import(backup_file) 
    $logger.info("Migrated #{@src.dbname}")
  end
end

class Hash
  def to_o
    JSON.parse(to_json, object_class: OpenStruct)
  end
end

def main
  config_file = ARGV[0]
  raise "Please provide a valid manifest. '#{config_file}' is not a valid file!" if config_file.nil? || !File.exist?(config_file)

  config = YAML.load_file(config_file)
  config = config.to_o

  # config logger
  $logger.level = :debug if config.debug 

  # migrate
  $logger.info('Building migrators ...')
  migrators = []
  dbnames = nil
  migration_groups = config.migration_groups
  migration_groups.each do |group|
    dbnames = group.source.databases

    src_host = group.source.host
    src_username = group.source.username
    src_password = group.source.password
    src_port = group.source.port

    dest_host = group.dest.host
    dest_username = group.dest.username
    dest_password = group.dest.password
    dest_port = group.dest.port

    dbnames.each do |dbname|
      src = Database.new(src_host, dbname, src_username, src_password, src_port)
      dest = Database.new(dest_host, dbname, dest_username, dest_password, dest_port)

      migrators.push(Migrator.new(src, dest))
    end
  end

  $logger.info('Starting migration ...')
  migrators.map(&:exec_migration)
  $logger.info('Done!')
end

main
