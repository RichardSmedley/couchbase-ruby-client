/* -*- Mode: C++; tab-width: 4; c-basic-offset: 4; indent-tabs-mode: nil -*- */
/*
 *     Copyright 2020 Couchbase, Inc.
 *
 *   Licensed under the Apache License, Version 2.0 (the "License");
 *   you may not use this file except in compliance with the License.
 *   You may obtain a copy of the License at
 *
 *       http://www.apache.org/licenses/LICENSE-2.0
 *
 *   Unless required by applicable law or agreed to in writing, software
 *   distributed under the License is distributed on an "AS IS" BASIS,
 *   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 *   See the License for the specific language governing permissions and
 *   limitations under the License.
 */

#pragma once

namespace couchbase::protocol
{
class select_bucket_response_body
{
  public:
    static const inline client_opcode opcode = client_opcode::select_bucket;

  public:
    bool parse(protocol::status,
               const header_buffer& header,
               std::uint8_t,
               std::uint16_t,
               std::uint8_t,
               const std::vector<uint8_t>&,
               const cmd_info&)
    {
        Expects(header[1] == static_cast<uint8_t>(opcode));
        return false;
    }
};

class select_bucket_request_body
{
  public:
    using response_body_type = select_bucket_response_body;
    static const inline client_opcode opcode = client_opcode::select_bucket;

  private:
    std::string key_;

  public:
    void bucket_name(std::string_view name)
    {
        key_ = name;
    }

    const std::string& key()
    {
        return key_;
    }

    const std::vector<std::uint8_t>& framing_extras()
    {
        static std::vector<std::uint8_t> empty;
        return empty;
    }

    const std::vector<std::uint8_t>& extras()
    {
        static std::vector<std::uint8_t> empty;
        return empty;
    }

    const std::vector<std::uint8_t>& value()
    {
        static std::vector<std::uint8_t> empty;
        return empty;
    }

    std::size_t size()
    {
        return key_.size();
    }
};

} // namespace couchbase::protocol
