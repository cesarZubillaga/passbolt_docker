require 'spec_helper'

describe 'passbolt_api service' do

  before(:all) do
    if ENV['GITLAB_CI']
      @mysql_image = Docker::Image.create('fromImage' => 'registry.gitlab.com/passbolt/passbolt-ci-docker-images/mariadb-10.3:latest')
    else
      @mysql_image = Docker::Image.create('fromImage' => 'mariadb:latest')
    end
    @mysql = Docker::Container.create(
      'Env' => [
        'MYSQL_ROOT_PASSWORD=test',
        'MYSQL_DATABASE=passbolt',
        'MYSQL_USER=passbolt',
        'MYSQL_PASSWORD=±!@#$%^&*()_+=-}{|:;<>?'
      ],
      "Healthcheck" => {
        "Test": [
          "CMD-SHELL",
          "mysqladmin ping --silent"
        ]
      },
      'Image' => @mysql_image.id)
    @mysql.start

    while @mysql.json['State']['Health']['Status'] != 'healthy'
      sleep 1
    end

    if ENV['GITLAB_CI']
      Docker.authenticate!(
        'username' => ENV['CI_REGISTRY_USER'].to_s,
        'password' => ENV['CI_REGISTRY_PASSWORD'].to_s,
        'serveraddress' => 'https://registry.gitlab.com/'
      )
      if ENV['ROOTLESS'] == 'true'
        @image = Docker::Image.create('fromImage' => "#{ENV['CI_REGISTRY_IMAGE']}:#{ENV['PASSBOLT_FLAVOUR']}-rootless-latest")
      else
        @image = Docker::Image.create('fromImage' => "#{ENV['CI_REGISTRY_IMAGE']}:#{ENV['PASSBOLT_FLAVOUR']}-root-latest")
      end
    else
      @image = Docker::Image.build_from_dir(ROOT_DOCKERFILES, { 'dockerfile' => $dockerfile, 'buildargs' => JSON.generate($buildargs) } )
    end

    @container = Docker::Container.create(
      'Env' => [
        "DATASOURCES_DEFAULT_HOST=#{@mysql.json['NetworkSettings']['IPAddress']}",
      ],
      'Binds' => $binds.append(
        "#{FIXTURES_PATH + '/passbolt.php'}:#{PASSBOLT_CONFIG_PATH + '/passbolt.php'}",
        "#{FIXTURES_PATH + '/public-test.key'}:#{PASSBOLT_CONFIG_PATH + 'gpg/unsecure.key'}",
        "#{FIXTURES_PATH + '/private-test.key'}:#{PASSBOLT_CONFIG_PATH + 'gpg/unsecure_private.key'}",
      ),
      'Image' => @image.id)

    @container.start
    @container.logs(stdout: true)

    set :docker_container, @container.id
    sleep 17
  end

  after(:all) do
    @mysql.kill
    @container.kill
  end

  let(:passbolt_host)     { @container.json['NetworkSettings']['IPAddress'] }
  let(:uri)               { "/healthcheck/status.json" }
  let(:curl)              { "curl -sk -o /dev/null -w '%{http_code}' -H 'Host: passbolt.local' https://#{passbolt_host}:#{$https_port}/#{uri}" }

  describe 'php service' do
    it 'is running supervised' do
      expect(service('php-fpm')).to be_running.under('supervisor')
    end
  end

  describe 'email cron' do
    it 'is running supervised' do
      expect(service('cron')).to be_running.under('supervisor')
    end
  end

  describe 'web service' do
    it 'is running supervised' do
      expect(service('nginx')).to be_running.under('supervisor')
    end

    it 'is listening on port 80' do
      expect(@container.json['Config']['ExposedPorts']).to have_key("#{$http_port}/tcp")
    end

    it 'is listening on port 443' do
      expect(@container.json['Config']['ExposedPorts']).to have_key("#{$https_port}/tcp")
    end
  end

  describe 'passbolt status' do
    it 'returns 200' do
      expect(command(curl).stdout).to eq '200'
    end
  end

  describe 'can not access outside webroot' do
    let(:uri) { '/vendor/autoload.php' }
    it 'returns 404' do
      expect(command(curl).stdout).to eq '404'
    end
  end

  describe 'hide information' do
    let(:curl) { "curl -Isk -H 'Host: passbolt.local' https://#{passbolt_host}:#{$https_port}/" }
    it 'hides php version' do
      expect(command("#{curl} | grep 'X-Powered-By: PHP'").stdout).to be_empty
    end

    it 'hides nginx version' do
      expect(command("#{curl} | grep 'server:'").stdout.strip).to match(/^server:\s+nginx.*$/)
    end
  end

end
