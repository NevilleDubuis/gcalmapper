require 'gcal_mapper/authentification/base'
require 'json'

module GcalMapper
  class Authentification
    #
    # make the authentification for service account and request data from google calendar.
    #
    class Assertion < Authentification::Base
      ASSERTION_SCOPE = 'https://www.google.com/calendar/feeds/'  # scope for assertion
      JWT_HEADER      = {'alg' => 'RS256', 'typ' => 'JWT'}  # header of the jwt to send
      ASSERTION_TYPE  = 'http://oauth.net/grant_type/jwt/1.0/bearer'  # url to specify which type of assertion


      attr_accessor :client_email   # the email given by google for the service account
      attr_accessor :user_email     # the email of the user to impersonate

      # New object
      #
      # @param [String] p12_file the path to the p12 key file
      # @param [String] client_email email from the api_consol
      # @param [String] user_email email from the impersonated user
      # @param [String] password p12 key password
      def initialize(p12_file, client_email, user_email, password)
        @client_email = client_email
        @p12_file = p12_file
        @user_email = user_email
        @password = password
        request_token
        @validity = Time.now.getutc.to_i
      end

      # give the acess token for th application and refresh if it is outdated
      #
      # @return [String] access token
      def access_token
        if Time.now.getutc.to_i - @validity > 3600
          refresh_token
        end

        @access_token
      end

      # refresh the token by asking for a new one
      #
      # @return [String] access token
      def refresh_token
        request_token
      end

      private
      # generate the JWT that must be include with the request acess token.
      # the format of the JWT is (base64url encoded header).(base64url encoded claim set).(base64url encoded signature)
      #
      # @return [String] the generate JWT.
      def generate_assertion()
        encoded_header = [JWT_HEADER.to_json].pack("m0").tr("+/", "-_")


        utc_time = Time.now.getutc.to_i
        claim = {
          'aud' => Authentification::REQUEST_URL,
          'scope'=> ASSERTION_SCOPE,
          'prn' => @user_email,
          'iat' => utc_time,
          'exp' => utc_time+3600,
          'iss' => @client_email
        }
        encoded_claim = [claim.to_json].pack("m0").tr("+/", "-_")
        begin
          p12 = OpenSSL::PKCS12.new(File.read(@p12_file), @password)
        rescue
          raise GcalMapper::AuthFileError
        end
        key = p12.key
        sign = key.sign(OpenSSL::Digest::SHA256.new, encoded_header + '.' + encoded_claim)
        encoded_sign = [sign].pack("m0").tr("+/", "-_")

        encoded_header + '.' + encoded_claim + '.' + encoded_sign
      end

      # Prepare all the parameters for sending the request token request to google
      # and save the token in instance variable.
      #
      # @return [Hash] the HTTP response.
      def request_token
        data = {
          'grant_type' => 'assertion',
          'assertion_type' => ASSERTION_TYPE,
          'assertion' => generate_assertion
        }
        options = {
          :method => :post,
          :headers => {'Content-Type' => 'application/x-www-form-urlencoded'},
          :parameters => data
        }
        req = GcalMapper::RestRequest.new(Authentification::REQUEST_URL, options)
        begin
          response = req.execute
        rescue
          raise GcalMapper::AuthentificationError
        end
        @valididity = Time.now.getutc.to_i

        @access_token = response['access_token']
      end

    end
  end
end