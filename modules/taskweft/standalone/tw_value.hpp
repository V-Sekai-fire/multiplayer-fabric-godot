// Recursive tagged-union value type for Taskweft standalone library.
// No Godot dependency — pure C++20.
#pragma once
#include <cmath>
#include <cstdint>
#include <memory>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

class TwValue {
public:
    enum class Type { NIL, BOOL, INT, FLOAT, STRING, ARRAY, DICT };
    using Array = std::vector<TwValue>;
    using Dict  = std::unordered_map<std::string, TwValue>;

private:
    Type    _type = Type::NIL;
    bool    _b    = false;
    int64_t _i    = 0;
    double  _f    = 0.0;
    std::string                 _s;
    std::unique_ptr<Array>      _arr;
    std::unique_ptr<Dict>       _dct;

public:
    TwValue() noexcept = default;
    TwValue(bool v) noexcept    : _type(Type::BOOL),   _b(v) {}
    TwValue(int v) noexcept     : _type(Type::INT),    _i(v) {}
    TwValue(int64_t v) noexcept : _type(Type::INT),    _i(v) {}
    TwValue(double v) noexcept  : _type(Type::FLOAT),  _f(v) {}
    TwValue(const char *v)      : _type(Type::STRING), _s(v) {}
    TwValue(std::string v)      : _type(Type::STRING), _s(std::move(v)) {}
    TwValue(Array v)            : _type(Type::ARRAY),  _arr(std::make_unique<Array>(std::move(v))) {}
    TwValue(Dict v)             : _type(Type::DICT),   _dct(std::make_unique<Dict>(std::move(v))) {}

    TwValue(const TwValue &o)
        : _type(o._type), _b(o._b), _i(o._i), _f(o._f), _s(o._s) {
        if (o._arr) _arr = std::make_unique<Array>(*o._arr);
        if (o._dct) _dct = std::make_unique<Dict>(*o._dct);
    }
    TwValue(TwValue &&) noexcept = default;
    TwValue &operator=(TwValue o) noexcept {
        using std::swap;
        swap(_type, o._type); swap(_b, o._b); swap(_i, o._i);
        swap(_f, o._f);       swap(_s, o._s);
        swap(_arr, o._arr);   swap(_dct, o._dct);
        return *this;
    }

    Type type()      const noexcept { return _type; }
    bool is_nil()    const noexcept { return _type == Type::NIL; }
    bool is_bool()   const noexcept { return _type == Type::BOOL; }
    bool is_int()    const noexcept { return _type == Type::INT; }
    bool is_float()  const noexcept { return _type == Type::FLOAT; }
    bool is_string() const noexcept { return _type == Type::STRING; }
    bool is_array()  const noexcept { return _type == Type::ARRAY; }
    bool is_dict()   const noexcept { return _type == Type::DICT; }
    bool is_number() const noexcept { return _type == Type::INT || _type == Type::FLOAT; }

    bool               as_bool()   const noexcept { return _b; }
    int64_t            as_int()    const noexcept { return _i; }
    double             as_float()  const noexcept { return _f; }
    double             as_number() const noexcept { return is_int() ? double(_i) : _f; }
    const std::string &as_string() const noexcept { return _s; }
    const Array       &as_array()  const          { return *_arr; }
          Array       &as_array()                 { return *_arr; }
    const Dict        &as_dict()   const          { return *_dct; }
          Dict        &as_dict()                  { return *_dct; }

    bool operator==(const TwValue &o) const noexcept {
        if (is_number() && o.is_number()) return as_number() == o.as_number();
        if (_type != o._type) return false;
        switch (_type) {
            case Type::NIL:    return true;
            case Type::BOOL:   return _b == o._b;
            case Type::INT:    return _i == o._i;
            case Type::FLOAT:  return _f == o._f;
            case Type::STRING: return _s == o._s;
            case Type::ARRAY:  return *_arr == *o._arr;
            case Type::DICT:   return false;
        }
        return false;
    }
    bool operator!=(const TwValue &o) const noexcept { return !(*this == o); }
    bool operator<(const TwValue &o) const noexcept {
        if (is_number() && o.is_number()) return as_number() < o.as_number();
        if (_type != o._type) return int(_type) < int(o._type);
        switch (_type) {
            case Type::INT:    return _i < o._i;
            case Type::FLOAT:  return _f < o._f;
            case Type::STRING: return _s < o._s;
            default:           return false;
        }
    }
    bool operator<=(const TwValue &o) const noexcept { return !(o < *this); }
    bool operator>(const TwValue &o) const noexcept  { return o < *this; }
    bool operator>=(const TwValue &o) const noexcept { return !(*this < o); }

    std::string to_string() const {
        std::ostringstream oss;
        switch (_type) {
            case Type::NIL:    return "nil";
            case Type::BOOL:   return _b ? "true" : "false";
            case Type::INT:    oss << _i;  return oss.str();
            case Type::FLOAT:  oss << _f;  return oss.str();
            case Type::STRING: return _s;
            case Type::ARRAY: {
                oss << "[";
                for (size_t i = 0; i < _arr->size(); i++) {
                    if (i) oss << ", ";
                    oss << (*_arr)[i].to_string();
                }
                oss << "]";
                return oss.str();
            }
            case Type::DICT: {
                oss << "{";
                bool first = true;
                for (auto &[k, v] : *_dct) {
                    if (!first) oss << ", ";
                    oss << k << ": " << v.to_string();
                    first = false;
                }
                oss << "}";
                return oss.str();
            }
        }
        return "nil";
    }
};
