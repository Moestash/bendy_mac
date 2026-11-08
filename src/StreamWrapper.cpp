#include "StreamWrapper.h"
#include "fp_cplug.h"
#include "fp_def.h"
#include <vector>
#include <algorithm>
#include <climits>
#include <cfloat>
#include <codecvt>
#include <cstring>
#include <limits>
#include <locale>
#include <stdexcept>

namespace {
#ifdef _WIN32
using WideCodecvt = std::codecvt_utf8_utf16<wchar_t>;
#else
using WideCodecvt = std::codecvt_utf8<wchar_t>;
#endif
// Windows saves wchar_t as UTF-16. macOS wchar_t is UTF-32, so the wire
// representation must be explicit to keep projects and presets portable.
std::u16string toUTF16(const std::wstring& value)
{
    std::wstring_convert<WideCodecvt> wide;
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> utf16;
    return utf16.from_bytes(wide.to_bytes(value));
}
std::wstring fromUTF16(const std::u16string& value)
{
    std::wstring_convert<WideCodecvt> wide;
    std::wstring_convert<std::codecvt_utf8_utf16<char16_t>, char16_t> utf16;
    return wide.from_bytes(utf16.to_bytes(value));
}
int stringLength(Stream& stream)
{
    int length = stream.readInt();
    if (length < 0 || length > 16 * 1024 * 1024)
        throw std::runtime_error("Invalid BENDY string length");
    return length;
}
}


StreamWrapper::StreamWrapper(IStream* data)
{
	_stream = data;
}

void StreamWrapper::advance(int bytes)
{
	LARGE_INTEGER li;
	li.QuadPart = bytes;
	_stream->Seek(li, STREAM_SEEK_CUR, 0);
}

int StreamWrapper::getPosition()
{
	LARGE_INTEGER li;
	li.QuadPart = 0;

	ULARGE_INTEGER pos;
	_stream->Seek(li, STREAM_SEEK_CUR, &pos);
	return (int)pos.QuadPart;
}

void StreamWrapper::setPosition(int bytes)
{
	LARGE_INTEGER li;
	li.QuadPart = bytes;
	_stream->Seek(li, STREAM_SEEK_SET, 0);
}

char StreamWrapper::readChar()
{
	char ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, sizeof(char), &read) != S_OK || read != sizeof(char))
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}

void StreamWrapper::writeChar(char value)
{
	_stream->Write(&value, sizeof(char), 0);
}

bool StreamWrapper::readBool()
{
	bool ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, 1, &read) != S_OK || read != 1)
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}
void StreamWrapper::writeBool(bool value)
{
	_stream->Write(&value, 1, 0);
}

unsigned short StreamWrapper::readUShort()
{
	unsigned short ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, sizeof(unsigned short), &read) != S_OK || read != sizeof(unsigned short))
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}

void StreamWrapper::writeUShort(unsigned short value)
{
	_stream->Write(&value, sizeof(unsigned short), 0);
}


int StreamWrapper::readInt()
{
	int ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, sizeof(int), &read) != S_OK || read != sizeof(int))
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}

void StreamWrapper::writeInt(int value)
{
	_stream->Write(&value, sizeof(int), 0);
}

unsigned int StreamWrapper::readUInt()
{
	unsigned int ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, sizeof(unsigned int), &read) != S_OK || read != sizeof(unsigned int))
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}

void StreamWrapper::writeUInt(unsigned int value)
{
	_stream->Write(&value, sizeof(unsigned int), 0);
}

float StreamWrapper::readFloat()
{
	float ret = 0;
	ULONG read = 0;
	if (_stream->Read(&ret, sizeof(float), &read) != S_OK || read != sizeof(float))
		throw std::runtime_error("Truncated BENDY state");

	return ret;
}
void StreamWrapper::writeFloat(float value)
{
	_stream->Write(&value, sizeof(float), 0);
}

std::wstring StreamWrapper::readString()
{
    const int length = stringLength(*this);
    std::u16string value(length, u'\0');
    ULONG read = 0;
    const ULONG bytes = static_cast<ULONG>(length * sizeof(char16_t));
    if (bytes && (_stream->Read(&value[0], bytes, &read) != S_OK || read != bytes))
        throw std::runtime_error("Truncated BENDY string");
    return fromUTF16(value);
}

void StreamWrapper::writeString(std::wstring value)
{
    const auto utf16 = toUTF16(value);
    writeInt(static_cast<int>(utf16.size()));
    const ULONG bytes = static_cast<ULONG>(utf16.size() * sizeof(char16_t));
    ULONG written = 0;
    if (bytes && (_stream->Write(utf16.data(), bytes, &written) != S_OK || written != bytes))
        throw std::runtime_error("Could not write BENDY string");
}

DataStream::DataStream(const void* data, int size)
{
	_data = new char[size];
	memcpy(_data, data, size);
	_position = 0;
	_size = size;
}

DataStream::DataStream(int startingSize)
	:_position(0)
{
	_data = new char[startingSize];
	memset(_data, 0, startingSize);
	_size = startingSize;
}

DataStream::~DataStream()
{
	if (_data != nullptr)
	{
		delete[] _data;
		_data = nullptr;
	}
}

void DataStream::advance(int bytes)
{
	_position += bytes;
	if (_position < 0 || _position > _size) throw std::runtime_error("Invalid BENDY stream position");
}

int DataStream::getPosition()
{
	return _position;
}

void DataStream::setPosition(int bytes)
{
	_position = bytes;
	if (_position < 0)
		_position = 0;
	if (_position > _size)
		_position = _size;
}

char DataStream::readChar()
{
	if (sizeof(char) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	char c = _data[_position];
	_position++;
	return c;
}

void DataStream::writeChar(char value)
{
	ensure(sizeof(value));
	_data[_position] = value;
	_position += sizeof(value);
}

bool DataStream::readBool()
{
	if (sizeof(bool) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	bool c;
	std::memcpy(&c, _data + _position, sizeof(c));
	_position += sizeof(c);
	return c;
}
void DataStream::writeBool(bool value)
{
	ensure(sizeof(value));
	std::memcpy(_data + _position, &value, sizeof(value));
	_position += sizeof(value);
}

unsigned short DataStream::readUShort()
{
	if (sizeof(unsigned short) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	unsigned short c;
	std::memcpy(&c, _data + _position, sizeof(c));
	_position += sizeof(c);
	return c;
}

void DataStream::writeUShort(unsigned short value)
{
	ensure(sizeof(value));
	std::memcpy(_data + _position, &value, sizeof(value));
	_position += sizeof(value);
}


int DataStream::readInt()
{
	if (sizeof(int) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	int c;
	std::memcpy(&c, _data + _position, sizeof(c));
	_position += sizeof(c);
	return c;
}

void DataStream::writeInt(int value)
{
	ensure(sizeof(value));
	std::memcpy(_data + _position, &value, sizeof(value));
	_position += sizeof(value);
}

unsigned int DataStream::readUInt()
{
	if (sizeof(unsigned int) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	unsigned int c;
	std::memcpy(&c, _data + _position, sizeof(c));
	_position += sizeof(c);
	return c;
}

void DataStream::writeUInt(unsigned int value)
{
	ensure(sizeof(value));
	std::memcpy(_data + _position, &value, sizeof(value));
	_position += sizeof(value);
}

float DataStream::readFloat()
{
	if (sizeof(float) > static_cast<size_t>(_size - _position)) throw std::runtime_error("Truncated BENDY state");
	float c;
	std::memcpy(&c, _data + _position, sizeof(c));
	_position += sizeof(c);
	return c;
}

void DataStream::writeFloat(float value)
{
	ensure(sizeof(value));
	std::memcpy(_data + _position, &value, sizeof(value));
	_position += sizeof(value);
}

std::wstring DataStream::readString()
{
    const int length = stringLength(*this);
    const int bytes = length * sizeof(char16_t);
    if (bytes > _size - _position)
        throw std::runtime_error("Truncated BENDY string");
    std::u16string value(length, u'\0');
    if (bytes) std::memcpy(&value[0], _data + _position, bytes);
    _position += bytes;
    return fromUTF16(value);
}

void DataStream::writeString(std::wstring value)
{
    const auto utf16 = toUTF16(value);
    writeInt(static_cast<int>(utf16.size()));
    const int bytes = static_cast<int>(utf16.size() * sizeof(char16_t));
    ensure(bytes);
    std::memcpy(_data + _position, utf16.data(), bytes);
    _position += bytes;
}

void DataStream::ensure(int additionalSize)
{
    if (additionalSize < 0 || _position > INT_MAX - additionalSize)
        throw std::runtime_error("BENDY state is too large");
    const int needed = _position + additionalSize;
    if (needed > _size)
    {
        const int newSize = (std::max)(needed, _size <= INT_MAX / 2 ? _size * 2 : INT_MAX);
        char* resize = new char[newSize]();
        std::memcpy(resize, _data, _size);
        delete[] _data;
        _data = resize;
        _size = newSize;
    }
}
