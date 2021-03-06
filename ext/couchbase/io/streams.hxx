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

#include <functional>

#include <asio.hpp>
#include <asio/ssl.hpp>

namespace couchbase::io
{

class stream_impl
{
  protected:
    asio::strand<asio::io_context::executor_type> strand_;
    bool tls_;

  public:
    stream_impl(asio::io_context& ctx, bool is_tls)
      : strand_(asio::make_strand(ctx))
      , tls_(is_tls)
    {
    }

    virtual ~stream_impl() = default;

    [[nodiscard]] std::string_view log_prefix() const
    {
        return tls_ ? "tls" : "plain";
    }

    [[nodiscard]] virtual bool is_open() const = 0;

    virtual void close() = 0;

    virtual void set_options() = 0;

    virtual void async_connect(const asio::ip::tcp::resolver::results_type::endpoint_type& endpoint,
                               std::function<void(std::error_code)>&& handler) = 0;

    virtual void async_write(std::vector<asio::const_buffer>& buffers, std::function<void(std::error_code, std::size_t)>&& handler) = 0;

    virtual void async_read_some(asio::mutable_buffer buffer, std::function<void(std::error_code, std::size_t)>&& handler) = 0;
};

class plain_stream_impl : public stream_impl
{
  private:
    asio::ip::tcp::socket stream_;

  public:
    explicit plain_stream_impl(asio::io_context& ctx)
      : stream_impl(ctx, false)
      , stream_(strand_)
    {
    }

    [[nodiscard]] bool is_open() const override
    {
        return stream_.is_open();
    }

    void close() override
    {
        stream_.close();
    }

    void set_options() override
    {
        stream_.set_option(asio::ip::tcp::no_delay{ true });
        stream_.set_option(asio::socket_base::keep_alive{ true });
    }

    void async_connect(const asio::ip::tcp::resolver::results_type::endpoint_type& endpoint,
                       std::function<void(std::error_code)>&& handler) override
    {
        return stream_.async_connect(endpoint, handler);
    }

    void async_write(std::vector<asio::const_buffer>& buffers, std::function<void(std::error_code, std::size_t)>&& handler) override
    {
        return asio::async_write(stream_, buffers, handler);
    }

    void async_read_some(asio::mutable_buffer buffer, std::function<void(std::error_code, std::size_t)>&& handler) override
    {
        return stream_.async_read_some(buffer, handler);
    }
};

class tls_stream_impl : public stream_impl
{
  private:
    asio::ssl::stream<asio::ip::tcp::socket> stream_;

  public:
    tls_stream_impl(asio::io_context& ctx, asio::ssl::context& tls)
      : stream_impl(ctx, true)
      , stream_(ctx, tls)
    {
    }

    [[nodiscard]] bool is_open() const override
    {
        return stream_.lowest_layer().is_open();
    }

    void close() override
    {
        stream_.lowest_layer().close();
    }

    void set_options() override
    {
        stream_.lowest_layer().set_option(asio::ip::tcp::no_delay{ true });
        stream_.lowest_layer().set_option(asio::socket_base::keep_alive{ true });
    }

    void async_connect(const asio::ip::tcp::resolver::results_type::endpoint_type& endpoint,
                       std::function<void(std::error_code)>&& handler) override
    {
        return stream_.lowest_layer().async_connect(endpoint, [this, handler](std::error_code ec_connect) mutable {
            if (ec_connect == asio::error::operation_aborted) {
                return;
            }
            if (ec_connect) {
                return handler(ec_connect);
            }
            stream_.async_handshake(asio::ssl::stream_base::client, [handler](std::error_code ec_handshake) mutable {
                if (ec_handshake == asio::error::operation_aborted) {
                    return;
                }
                return handler(ec_handshake);
            });
        });
    }

    void async_write(std::vector<asio::const_buffer>& buffers, std::function<void(std::error_code, std::size_t)>&& handler) override
    {
        return asio::async_write(stream_, buffers, handler);
    }

    void async_read_some(asio::mutable_buffer buffer, std::function<void(std::error_code, std::size_t)>&& handler) override
    {
        return stream_.async_read_some(buffer, handler);
    }
};

} // namespace couchbase::io
