local driver = require "pallene.driver"
local util = require "pallene.util"

local function compile(pallene_code)
    return function()
        assert(util.set_file_contents("__test__.pln", pallene_code))
        local ok, errors =
            driver.compile("pallenec-tests", "pln", "so", "__test__.pln")
        assert(ok, errors[1])
    end
end

local function run_test(test_script)
    util.set_file_contents("__test__script__.lua", util.render([[
        local test = require "__test__"
        ${TEST_SCRIPT}
    ]], {
        TEST_SCRIPT = test_script
    }))
    assert(util.execute("./lua/src/lua __test__script__.lua > __test__output__.txt"))
end

local function assert_test_output(expected)
    local output = assert(util.get_file_contents("__test__output__.txt"))
    assert.are.same(expected, output)
end

local function cleanup()
    os.remove("__test__.pln")
    os.remove("__test__.so")
    os.remove("__test__script__.lua")
    os.remove("__test__output__.txt")
end

describe("Pallene coder /", function()
    teardown(cleanup)

    describe("Empty program /", function()
        setup(compile(""))

        it("compiles", function() end)
    end)

    describe("Exported functions /", function()
        setup(compile([[
            export function f(): integer return 10 end
            local function g(): integer return 11 end
        ]]))

        it("does not export local functions", function()
            run_test([[
                assert(type(test.f) == "function")
                assert(type(test.g) == "nil")
            ]])
        end)
    end)

    describe("Literals /", function()
        setup(compile([[
            export function f_nil(): nil          return nil  end
            export function f_true(): boolean     return true end
            export function f_false(): boolean    return false end
            export function f_integer(): integer  return 17 end
            export function f_float(): float      return 3.14 end
            export function f_string(): string    return "Hello World" end
            export function pi(): float           return 3.141592653589793 end
            export function e(): float            return 2.718281828459045 end
            export function one_half(): float     return 1.0 / 2.0 end
        ]]))

        it("nil", function()
            run_test([[ assert(nil == test.f_nil()) ]])
        end)

        it("true", function()
            run_test([[ assert(true == test.f_true()) ]])
        end)

        it("false", function()
            run_test([[ assert(false == test.f_false()) ]])
        end)

        it("integer", function()
            run_test([[ assert(17 == test.f_integer()) ]])
        end)

        it("float", function()
            run_test([[ assert(3.14 == test.f_float()) ]])
        end)

        it("strings", function()
            run_test([[ assert("Hello World" == test.f_string()) ]])
        end)

        it("floating point literals are accurate", function()
            run_test([[
                local pi = 3.141592653589793
                local e  = 2.718281828459045
                assert(pi == test.pi())
                assert(e  == test.e())
                assert(pi*e*e == test.pi() * test.e() * test.e())
            ]])
        end)

        it("floating point literals are the right type in C", function()
            -- There was a bug where (1.0/2.0) became (1/2) in the generated C
            run_test([[
                assert(0.5 == test.one_half())
            ]])
        end)
    end)

    describe("Variables /", function()
        setup(compile([[
            export function fst(x:integer, y:integer): integer return x end
            export function snd(x:integer, y:integer): integer return y end

            local n = 0
            export function next_n(): integer
                n = n + 1
                return n
            end
        ]]))

        it("local variables", function()
            run_test([[
                assert(10 == test.fst(10, 20))
                assert(20 == test.snd(10, 20))
            ]])
        end)

        it("global variables", function()
            run_test([[
                assert(1 == test.next_n())
                assert(2 == test.next_n())
                assert(3 == test.next_n())
            ]])
        end)
    end)

    describe("Function calls /", function()
        setup(compile([[
            export function f0(): integer
                return 17
            end

            export function g0(): integer
                return f0()
            end

            -----------

            export function f1(x:integer): integer
                return x
            end

            export function g1(x:integer): integer
                return f1(x)
            end

            -----------

            export function f2(x:integer, y:integer): integer
                return x+y
            end

            export function g2(x:integer, y:integer): integer
                return f2(x, y)
            end

            -----------

            export function gcd(a:integer, b:integer): integer
                if b == 0 then
                   return a
                else
                   return gcd(b, a % b)
                end
            end

            -----------

            export function even(x: integer): boolean
                if x == 0 then
                    return true
                else
                    return odd(x-1)
                end
            end

            export function odd(x: integer): boolean
                if x == 0 then
                    return false
                else
                    return even(x-1)
                end
            end

            -----------

            export function skip_a() end
            export function skip_b() skip_a(); skip_a() end

            -----------

            export function ignore_return(): integer
                even(1)
                return 17
            end

            export function ignore_return_builtin(): integer
                math.sqrt(1.0)
                return 18
            end

        ]]))

        it("no parameters", function()
            run_test([[ assert(17 == test.g0()) ]])
        end)

        it("one parameter", function()
            run_test([[ assert(17 == test.g1(17)) ]])
        end)

        it("multiple parameters", function()
            run_test([[ assert(17 == test.g2(16, 1)) ]])
        end)

        it("recursive calls", function()
            run_test([[ assert(3*5 == test.gcd(2*3*5, 3*5*7)) ]])
        end)

        it("mutually recursive calls", function()
            run_test([[
                for i = 0, 5 do
                    assert( (i%2 == 0) == test.even(i) )
                    assert( (i%2 == 1) == test.odd(i) )
                end
            ]])
        end)

        it("void functions", function()
            run_test([[ assert(0 == select("#", test.skip_b())) ]])
        end)

        it("unused return value", function()
            run_test([[ assert(17 == test.ignore_return()) ]])
        end)

        it("unused return value (builtin function)", function()
            run_test([[ assert(18 == test.ignore_return_builtin()) ]])
        end)

        -- Errors

        it("missing arguments", function()
            run_test([[
                local ok, err = pcall(test.g1)
                assert(string.find(err,
                    "wrong number of arguments to function 'g1', " ..
                    "expected 1 but received 0",
                    nil, true))
            ]])
        end)

        it("too many arguments", function()
            run_test([[
                local ok, err = pcall(test.g1, 10, 20)
                assert(string.find(err,
                    "wrong number of arguments to function 'g1', " ..
                    "expected 1 but received 2",
                    nil, true))
            ]])
        end)

        it("type of argument", function()
            -- Also sees if error messages say "float" and "integer"
            -- instead of "number"
            run_test([[
                local ok, err = pcall(test.g1, 3.14)
                assert(string.find(err,
                    "wrong type for argument 'x', " ..
                    "expected integer but found float",
                    nil, true))
            ]])
        end)
    end)

    describe("First class functions /", function()
        setup(compile([[
            export function inc(x:integer): integer   return x + 1   end
            export function dec(x:integer): integer   return x - 1   end

            export function get_inc(): integer->integer
                return inc
            end

            --------

            export function call(
                f : integer -> integer,
                x : integer
            ) :  integer
                return f(x)
            end

            --------

            local f: integer->integer = inc

            export function setf(g:integer->integer): ()
                f = g
            end

            export function getf(): integer->integer
                return f
            end

            export function callf(x:integer): integer
                return f(x)
            end
        ]]))

        it("Object identity", function()
            run_test([[
                assert(test.inc == test.get_inc())
            ]])
        end)

        it("Can call non-static functions", function()
            run_test([[
                local f = function(x) return x * 20 end
                assert(200 == test.call(f, 10))
                assert(201 == test.call(test.inc, 200))
            ]])
        end)

        it("Can call global function vars", function()
            run_test([[
                assert(11 == test.callf(10))
            ]])
        end)

        it("Can get, set, and call global function vars", function()
            run_test([[
                assert(11 == test.getf()(10))
                test.setf(test.dec)
                assert( 9 == test.getf()(10))
            ]])
        end)

        it("Type-checks Lua functions", function()
            run_test([[
                local f = function(x) return "hello" end
                local ok, err = pcall(test.call, f, 0)
                assert(not ok)
                assert(string.find(err,
                    "wrong type for return value #1, "..
                    "expected integer but found string",
                    nil, true))
            ]])
        end)
    end)

    describe("Unary Operators /", function()

        local tests = {
            { "neg_i", "-",   "integer", "integer" },
            { "bnot",  "~",   "integer", "integer" },
            { "not_b", "not", "boolean", "boolean" },
            { "not_a", "not", "any",     "any"   },
        }

        local pallene_code = {}
        local test_scripts = {}

        for i, test in ipairs(tests) do
            local name, op, typ, rtyp = test[1], test[2], test[3], test[4]

            pallene_code[i] = util.render([[
                export function $name (x: $typ): $rtyp
                    return $op x
                end
            ]], {
                name = name, typ = typ, rtyp = rtyp, op = op,
            })

            test_scripts[name] = util.render([[
                local test_op = require "spec.coder_test_operators"
                test_op.check_unop(
                    $op_str,
                    function(x) return $op x end,
                    test.${name},
                    $typ_str
                )
            ]],{
                name = name,
                op = op,
                op_str = string.format("%q", op),
                typ_str = string.format("%q", typ),
            })
        end

        setup(compile(table.concat(pallene_code, "\n")))

        for _, test in ipairs(tests) do
            local name = test[1]
            it(name, function() run_test(test_scripts[name]) end)
        end
    end)

    describe("Binary Operators /", function()

        local tests = {

            -- Non-comparison operators, same order as checker.lua

            { "add_ii",    "+",   "integer", "integer", "integer" },
            { "add_if",    "+",   "integer", "float",   "float" },
            { "add_fi",    "+",   "float",   "integer", "float" },
            { "add_ff",    "+",   "float",   "float",   "float" },

            { "sub_ii",    "-",   "integer", "integer", "integer" },
            { "sub_if",    "-",   "integer", "float",   "float" },
            { "sub_fi",    "-",   "float",   "integer", "float" },
            { "sub_ff",    "-",   "float",   "float",   "float" },

            { "mul_ii",    "*",   "integer", "integer", "integer" },
            { "mul_if",    "*",   "integer", "float",   "float" },
            { "mul_fi",    "*",   "float",   "integer", "float" },
            { "mul_ff",    "*",   "float",   "float",   "float" },

            { "mod_ii",    "%",   "integer", "integer", "integer" },
            { "mod_if",    "%",   "integer", "float",   "float" },
            { "mod_fi",    "%",   "float",   "integer", "float" },
            { "mod_ff",    "%",   "float",   "float",   "float" },

            { "intdiv_ii", "//",  "integer", "integer", "integer" },
            { "intdiv_if", "//",  "integer", "float",   "float" },
            { "intdiv_fi", "//",  "float",   "integer", "float" },
            { "intdiv_ff", "//",  "float",   "float",   "float" },


            { "fltdiv_ii", "/",   "integer", "integer", "float" },
            { "fltdiv_ff", "/",   "float",   "float",   "float" },

            { "pow_ii",    "^",   "integer", "integer", "float" },
            { "pow_ff",    "^",   "float",   "float",   "float" },

            { "and_bb",    "and", "boolean", "boolean", "boolean" },
            { "or_bb",     "or",  "boolean", "boolean", "boolean" },

            { "and_aa",    "and", "any", "any", "any" },
            { "or_aa",     "or",  "any", "any", "any" },

            { "bor",       "|",   "integer", "integer", "integer" },
            { "band",      "&",   "integer", "integer", "integer" },
            { "bxor",      "~",   "integer", "integer", "integer" },
            { "lshift",    "<<",  "integer", "integer", "integer" },
            { "rshift",    ">>",  "integer", "integer", "integer" },

            { "concat_ss", "..",  "string",  "string",  "string" },

            -- Comparison operators, same order as types.lua
            -- Nil and Record are tested separately.

            { "eq_any", "==",  "any", "any", "boolean" },
            { "ne_any", "~=",  "any", "any", "boolean" },

            { "eq_boolean", "==",  "boolean", "boolean", "boolean" },
            { "ne_boolean", "~=",  "boolean", "boolean", "boolean" },

            { "eq_integer", "==",  "integer", "integer", "boolean" },
            { "ne_integer", "~=",  "integer", "integer", "boolean" },
            { "lt_integer", "<",   "integer", "integer", "boolean" },
            { "gt_integer", ">",   "integer", "integer", "boolean" },
            { "le_integer", "<=",  "integer", "integer", "boolean" },
            { "ge_integer", ">=",  "integer", "integer", "boolean" },

            { "eq_float", "==",  "float", "float", "boolean" },
            { "ne_float", "~=",  "float", "float", "boolean" },
            { "lt_float", "<",   "float", "float", "boolean" },
            { "gt_float", ">",   "float", "float", "boolean" },
            { "le_float", "<=",  "float", "float", "boolean" },
            { "ge_float", ">=",  "float", "float", "boolean" },

            { "eq_string", "==",  "string", "string", "boolean" },
            { "ne_string", "~=",  "string", "string", "boolean" },
            { "lt_string", "<",   "string", "string", "boolean" },
            { "gt_string", ">",   "string", "string", "boolean" },
            { "le_string", "<=",  "string", "string", "boolean" },
            { "ge_string", ">=",  "string", "string", "boolean" },

            { "eq_function", "==", "(integer, integer) -> integer",
                                   "(integer, integer) -> integer",
                                   "boolean" },
            { "ne_function", "~=", "(integer, integer) -> integer",
                                   "(integer, integer) -> integer",
                                   "boolean" },

            { "eq_array", "==", "{integer}", "{integer}", "boolean" },
            { "ne_array", "~=", "{integer}", "{integer}", "boolean" },

            { "eq_table", "==", "{x: integer, y: integer}",
                                "{x: integer, y: integer}", "boolean" },
            { "ne_table", "~=", "{x: integer, y: integer}",
                                "{x: integer, y: integer}", "boolean" },
        }

        local pallene_code = {}
        local test_scripts = {}

        for i, test in ipairs(tests) do
            local name, op, typ1, typ2, rtyp =
                test[1], test[2], test[3], test[4], test[5]

            pallene_code[i] = util.render([[
                export function $name (x: $typ1, y:$typ2): $rtyp
                    return x ${op} y
                end
            ]], {
                name = name, typ1 = typ1, typ2=typ2, rtyp = rtyp, op = op,
            })

            test_scripts[name] = util.render([[
                local test_op = require "spec.coder_test_operators"
                test_op.check_binop(
                    $op_str,
                    function(x, y) return (x $op y) end,
                    test.${name},
                    $typ1_str,
                    $typ2_str
                )
            ]],{
                name = name,
                op = op,
                op_str = string.format("%q", op),
                typ1_str = string.format("%q", typ1),
                typ2_str = string.format("%q", typ2),
            })
        end

        setup(compile(table.concat(pallene_code, "\n")))

        for _, test in ipairs(tests) do
             local name = test[1]
             it(name, function() run_test(test_scripts[name]) end)
        end
    end)

    describe("Nil equality", function()
        setup(compile([[
            export function eq_nil(x: nil, y: nil): boolean
                return x == y
            end

            export function ne_nil(x: nil, y: nil): boolean
                return x ~= y
            end

            export function eq_any(x: any, y: any): boolean
                return x == y
            end
        ]]))

        it("==", function()
            run_test([[
                assert(true == test.eq_nil(nil, nil))
                assert(true == test.eq_nil(nil, ({})[1]))
            ]])
        end)

        it("~=", function()
            run_test([[
                assert(true == test.eq_nil(nil, nil))
                assert(true == test.eq_nil(nil, ({})[1]))
            ]])
        end)

        it("is not equal to false", function()
            run_test([[
                assert(false == test.eq_any(nil, false))
            ]])
        end)
    end)

    describe("Record equality", function()
        setup(compile([[
            record Point
                x: float
                y: float
            end

            export function points(): {Point}
                return {
                    { x = 1.0, y = 2.0 },
                    { x = 1.0, y = 2.0 },
                    { x = 3.0, y = 4.0 },
                }
            end

            export function eq_point(p: Point, q: Point): boolean
                return p == q
            end

            export function ne_point(p: Point, q: Point): boolean
                return p ~= q
            end
        ]]))

        it("==", function()
            run_test([[
                local p = test.points()
                for i = 1, #p do
                    for j = 1, #p do
                        local ok = (i == j)
                        assert(ok == test.eq_point(p[i], p[j]))
                    end
                end
            ]])
        end)

        it("~=", function()
            run_test([[
                local p = test.points()
                for i = 1, #p do
                    for j = 1, #p do
                        local ok = (i ~= j)
                        assert(ok == test.ne_point(p[i], p[j]))
                    end
                end
            ]])
        end)
    end)

    describe("Coercions with dynamic type /", function()

        local tests = {
            { "boolean"  , "boolean",         "true"},
            { "integer"  , "integer",         "17"},
            { "float"    , "float",           "3.14"},
            { "string"   , "string",          "'hello'"},
            { "function" , "integer->string", "tostring"},
            { "array"    , "{integer}",       "{10,20}"},
            { "table"    , "{x: integer}",    "{x = 1}"},
            { "record"   , "Empty",           "test.new_empty()"},
            { "any"      , "any",             "17"},
        }

        local record_decls = [[
            record Empty
            end
            export function new_empty(): Empty
                return {}
            end
        ]]

        local pallene_code = {}
        local test_to      = {}
        local test_from    = {}

        for i, test in pairs(tests) do
            local name, typ, value = test[1], test[2], test[3]

            pallene_code[i] = util.render([[
                export function from_${name}(x: ${typ}): any
                    return (x as any)
                end

                export function to_${name}(x: any): ${typ}
                    return (x as ${typ})
                end
            ]], {
                name = name,
                typ = typ,
            })

            test_to[name] = util.render([[
                local x = ${value}
                assert(x == test.from_${name}(x))
            ]], {
                name = name,
                value = value
            })

            test_from[name] = util.render([[
                local x = ${value}
                assert(x == test.from_${name}(x))
            ]], {
                name = name,
                value = value
            })
        end

        setup(compile(
            record_decls .. "\n" ..
            table.concat(pallene_code, "\n")
        ))

        for _, test in ipairs(tests) do
            local name = test[1]
            it(name .. "->any", function() run_test(test_to[name]) end)
        end

        for _, test in ipairs(tests) do
            local name = test[1]
            it("any->" .. name, function() run_test(test_from[name]) end)
        end

        it("detects downcast error", function()
            run_test([[
                local ok, err = pcall(test.to_integer, "hello")
                assert(not ok)
                assert(string.find(err,
                    "wrong type for downcasted value", nil, true))
            ]])
        end)
    end)

    describe("Statements /", function()
        setup(compile([[
            export function stat_blocks(): integer
                local a = 1
                local b = 2
                do
                    local a = 3
                    b = a
                    a = b + 1
                end
                return a + b
            end

            export function sign(x: integer) : integer
                if x < 0 then
                    return -1
                elseif x == 0 then
                    return 0
                else
                    return 1
                end
            end

            export function abs(x: integer) : integer
                if x >= 0 then
                    return x
                end
                return -x
            end

            export function factorial_while(n: integer): integer
                local r = 1
                while n > 0 do
                    r = r * n
                    n = n - 1
                end
                return r
            end

            export function factorial_int_for_inc(n: integer): integer
                local res = 1
                for i = 1, n do
                    res = res * i
                end
                return res
            end

            export function factorial_int_for_dec(n: integer): integer
                local res = 1
                for i = n, 1, -1 do
                    res = res * i
                end
                return res
            end

            export function factorial_float_for_inc(n: float): float
                local res = 1.0
                for i = 1.0, n do
                    res = res * i
                end
                return res
            end

            export function factorial_float_for_dec(n: float): float
                local res = 1.0
                for i = n, 1.0, -1.0 do
                    res = res * i
                end
                return res
            end

            export function repeat_until(): integer
                local x = 0
                repeat
                    x = x + 1
                    local limit = x * 10
                until limit >= 100
                return x
            end

            export function break_while() : integer
                while true do break end
                return 17
            end

            export function break_repeat() : integer
                repeat break until false
                return 17
            end

            export function break_for(): integer
                local x = 0
                for i = 1, 10 do
                    x = x + i
                    break
                end
                return x
            end

            export function nested_break(x:boolean): integer
                while true do
                    while true do
                        break
                        return 10
                    end
                    if x then
                        break
                        return 20
                    else
                        return 30
                    end
                end
                return 40
            end

        ]]))

        it("Block, Assign, Decl", function()
            run_test([[ assert(4 == test.stat_blocks()) ]])
        end)

        it("If statement (with else)", function()
            run_test([[ assert(-1 == test.sign(-10)) ]])
            run_test([[ assert( 0 == test.sign(  0)) ]])
            run_test([[ assert( 1 == test.sign( 10)) ]])
        end)

        it("If statement (without else)", function()
            run_test([[ assert(10 == test.abs(-10)) ]])
            run_test([[ assert( 0 == test.abs(  0)) ]])
            run_test([[ assert(10 == test.abs( 10)) ]])
        end)

        it("While", function()
            run_test([[ assert(720 == test.factorial_while(6)) ]])
        end)

        it("For loop (integer) (going up)", function()
            run_test([[ assert(720 == test.factorial_int_for_inc(6)) ]])
        end)

        it("For loop (integer) (going down)", function()
            run_test([[ assert(720 == test.factorial_int_for_dec(6)) ]])
        end)

        it("For loop (float) (going up)", function()
            run_test([[ assert(720.0 == test.factorial_float_for_inc(6.0)) ]])
        end)

        it("For loop (float) (going down)", function()
            run_test([[ assert(720.0 == test.factorial_float_for_dec(6.0)) ]])
        end)

        it("Repeat until", function()
            run_test([[ assert(10 == test.repeat_until()) ]])
        end)

        it("Break while loop", function()
            run_test([[ assert(17 == test.break_while()) ]])
        end)

        it("Break repeat-until loop", function()
            run_test([[ assert(17 == test.break_repeat()) ]])
        end)

        it("Break for loop", function()
            run_test([[ assert(1 == test.break_for()) ]])
        end)
        it("Nested break", function()
            run_test([[ assert(40 == test.nested_break(true)) ]])
        end)
    end)

    describe("Arrays /", function()
        setup(compile([[
            export function newarr(): {integer}
                return {10,20,30}
            end

            export function len(xs:{integer}): integer
                return #xs
            end

            export function geti(arr: {integer}, i: integer): integer
                return arr[i]
            end

            export function seti(arr: {integer}, i: integer, v: integer)
                arr[i] = v
            end

            export function insert(xs: {any}, v:any): ()
                xs[#xs + 1] = v
            end

            export function remove(xs: {any}): ()
                xs[#xs] = nil
            end

            export function getany(xs: {any}, i:integer): any
                return xs[i]
            end

            export function getnil(xs: {nil}, i: integer): nil
                return xs[i]
            end
        ]]))

        it("literals", function()
            run_test([[
                local t = test.newarr()
                assert(type(t) == "table")
                assert(#t == 3)
                assert(10 == t[1])
                assert(20 == t[2])
                assert(30 == t[3])
            ]])
        end)

        it("length operator (#)", function()
            run_test([[
                assert(0 == test.len({}))
                assert(1 == test.len({10}))
                assert(2 == test.len({10, 20}))
            ]])
        end)

        it("get", function()
            run_test([[
                local arr = {10, 20, 30}
                assert(10 == test.geti(arr, 1))
                assert(20 == test.geti(arr, 2))
                assert(30 == test.geti(arr, 3))
            ]])
        end)

        it("set", function()
            run_test( [[
                local arr = {10, 20, 30}
                test.seti(arr, 2, 123)
                assert( 10 == arr[1])
                assert(123 == arr[2])
                assert( 30 == arr[3])
            ]])
        end)

        it("checks type tags in get", function()
            run_test([[
                local arr = {10, 20, "hello"}

                local ok, err = pcall(test.geti, arr, 3)
                assert(not ok)
                assert(
                    string.find(err, "wrong type for array element", nil, true))
            ]])
        end)

        it("insert", function()
            run_test([[
                local arr = {}
                for i = 1, 50 do
                    test.insert(arr, 10*i)
                    assert(i == #arr)
                    for j = 1, i do
                        assert(10*j == arr[j])
                    end
                end
            ]])
        end)

        it("remove", function()
            run_test([[
                local arr = {}
                for i = 1, 100 do
                    arr[i] = 10*i
                end
                for i = 99, 50, -1 do
                    test.remove(arr)
                    assert(i == #arr)
                    for j = 1, i do
                        assert(10*j == arr[j])
                    end
                end
            ]])
        end)

        it("out-of bounds get is a tag error", function()
            run_test([[
                local arr = {10, 20, 30}

                local ok, err = pcall(test.geti, arr, 0)
                assert(not ok)
                assert(string.find(err, "invalid index", nil, true))

                local ok, err = pcall(test.geti, arr, 4)
                assert(not ok)
                assert(string.find(err, "wrong type for array element", nil, true))

                table.remove(arr)
                local ok, err = pcall(test.geti, arr, 3)
                assert(not ok)
                assert(string.find(err, "wrong type for array element", nil, true))
            ]])
        end)

        it("{nil}: in-bounds get nil", function()
            run_test([[ assert(nil == test.getnil({10, nil, 30}, 2)) ]])
        end)

        it("{nil}: out-of-bounds get nil", function()
            run_test([[ assert(nil == test.getnil({10, nil, 30}, 4)) ]])
        end)

        it("{any}: get non-nil", function()
            run_test([[ assert(10  == test.getany({10, nil, 30}, 1)) ]])
        end)

        it("{any}: in-bounds get nil", function()
            run_test([[ assert(nil == test.getany({10, nil, 30}, 2)) ]])
        end)

        it("{any}: out-of-bounds get nil", function()
            run_test([[ assert(nil == test.getany({10, nil, 30}, 4)) ]])
        end)

        it("length operator rejects arrays with a metatable", function()
            run_test([[
                local arr = {}
                setmetatable(arr, { __len = function(self) return 42 end })
                local ok, err = pcall(test.len, arr)
                assert(not ok)
                assert(string.find(err, "must not have a metatable", nil, true))
            ]])
        end)

        it("indexing operator rejects arrays with a metatable", function()
            run_test([[
                local arr = {}
                setmetatable(arr, { __index = function(self, k) return 42 end })
                local ok, err = pcall(test.getany, arr, 1)
                assert(not ok)
                assert(string.find(err, "must not have a metatable", nil, true))
            ]])
        end)
    end)

    describe("Tables /", function()
        local maxlenfield = string.rep('a', 40)

        setup(compile([[
            typealias point = {x: integer, y: integer}

            export function newpoint(): point
                return {x = 10, y = 20}
            end

            export function getx(p: point): integer
                return p.x
            end

            export function gety(p: point): integer
                return p.y
            end

            export function setx(p: point, v: integer)
                p.x = v
            end

            export function sety(p: point, v: integer)
                p.y = v
            end

            export function getany(t: {x: any}): any
                return t.x
            end

            export function setany(t: {x: any}, v: any)
                t.x = v
            end

            export function getnil(t: {x: nil}): nil
                return t.x
            end

            export function setnil(t: {x: nil})
                t.x = nil
            end

            export function getmax(t: {]].. maxlenfield ..[[: integer}): integer
                return t.]].. maxlenfield ..[[
            end
        ]]))

        it("has literals", function()
            run_test([[
                local t = test.newpoint()
                assert(type(t) == "table")
                assert(10 == t.x)
                assert(20 == t.y)
            ]])
        end)

        it("gets", function()
            run_test([[
                local p = {x = 10, y = 20}
                assert(10 == test.getx(p))
                assert(20 == test.gety(p))

                p.x = "hello"
                assert("hello" == test.getany(p))

                p.x = nil
                assert(nil == test.getany(p))
                assert(nil == test.getnil(p))
            ]])
        end)

        it("sets", function()
            run_test([[
                local p = {}
                test.setx(p, 30)
                test.sety(p, 40)
                assert(30 == p.x)
                assert(40 == p.y)

                test.setnil(p)
                assert(nil == p.x)

                test.setany(p, "hello")
                assert("hello", p.x)
            ]])
        end)

        it("checks type tags in get", function()
            run_test([[
                local p = {x = 10, y = "hello"}
                local ok, err = pcall(test.gety, p)
                assert(not ok)
                assert(
                    string.find(err, "wrong type for table field", nil, true))
            ]])
        end)

        it("works with fields with the max length", function()
            run_test([[
                local t = {]].. maxlenfield ..[[ = 10}
                assert(10 == test.getmax(t))
            ]])
        end)

        it("table field access rejects tables with a metatable", function()
            run_test([[
                local tab = {}
                setmetatable(tab, { __index = function(self, k) return 42 end })
                local ok, err = pcall(test.getany, tab)
                assert(not ok)
                assert(string.find(err, "must not have a metatable", nil, true))
            ]])
        end)

        it("table field access rejects tables with a metatable", function()
            run_test([[
                local tab = {}
                setmetatable(tab, { __index = function(self, k) return 42 end })
                local ok, err = pcall(test.getnil, tab)
                assert(not ok)
                assert(string.find(err, "must not have a metatable", nil, true))
            ]])
        end)
    end)

    describe("Strings", function()
        setup(compile([[
            export function len(s:string): integer
                return #s
            end
        ]]))

        it("length operator (#)", function()
            run_test([[ assert( 0 == test.len("")) ]])
            run_test([[ assert( 1 == test.len("H")) ]])
            run_test([[ assert(11 == test.len("Hello World")) ]])
        end)
    end)

    describe("Typealias", function()
        setup(compile([[
            typealias Float = float
            typealias FLOAT = float

            export function Float2float(x: Float): float return x end
            export function float2Float(x: float): Float return x end
            export function Float2FLOAT(x: Float): FLOAT return x end

            record point
                x: Float
            end

            typealias Point = point
            typealias Points = {Point}

            export function newPoint(x: Float): Point
                return {x = x}
            end

            export function get(p: Point): FLOAT
                return p.x
            end

            export function addPoint(ps: Points, p: Point)
                ps[#ps + 1] = p
            end
        ]]))

        it("converts between typealiases of the same type", function()
            run_test([[
                assert(1.1 == test.Float2float(1.1))
                assert(1.1 == test.float2Float(1.1))
                assert(1.1 == test.Float2FLOAT(1.1))
            ]])
        end)

        it("creates a records with typealiases", function()
            run_test([[
                local p = test.newPoint(1.1)
                assert(1.1 == test.get(p))
            ]])
        end)

        it("manipulates typealias of an array", function()
            run_test([[
                local p = test.newPoint(1.1)
                local ps = {}
                test.addPoint(ps, p)
                assert(p == ps[1])
            ]])
        end)
    end)

    describe("Records", function()
        setup(compile([[
            record Foo
                x: integer
                y: {integer}
            end

            export function make_foo(x: integer, y: {integer}): Foo
                return { x = x, y = y }
            end

            export function get_x(foo: Foo): integer
                return foo.x
            end

            export function set_x(foo: Foo, x: integer)
                foo.x = x
            end

            export function get_y(foo: Foo): {integer}
                return foo.y
            end

            export function set_y(foo: Foo, y: {integer})
                foo.y = y
            end

            record Prim
                x: integer
            end

            export function make_prim(x: integer): Prim
                return { x = x }
            end

            record Gc
                x: {integer}
            end

            export function make_gc(x: {integer}): Gc
                return { x = x }
            end

            record Empty
            end

            export function make_empty(): Empty
                return {}
            end
        ]]))

        it("create records", function()
            run_test([[
                local foo = test.make_foo(123, {})
                assert("userdata" == type(foo))
            ]])
        end)

        it("get/set primitive fields in pallene", function()
            run_test([[
                local foo = test.make_foo(123, {})
                assert(123 == test.get_x(foo))
                test.set_x(foo, 456)
                assert(456 == test.get_x(foo))
            ]])
        end)

        it("get/set gc fields in pallene", function()
            run_test([[
                local a = {}
                local b = {}
                local foo = test.make_foo(123, a)
                assert(a == test.get_y(foo))
                test.set_y(foo, b)
                assert(b == test.get_y(foo))
            ]])
        end)

        it("create records with only primitive fields", function()
            run_test([[
                local x = test.make_prim(123)
                assert("userdata" == type(x))
            ]])
        end)

        it("create records with only gc fields", function()
            run_test([[
                local x = test.make_gc({})
                assert("userdata" == type(x))
            ]])
        end)

        it("create empty records", function()
            run_test([[
                local x = test.make_empty()
                assert("userdata" == type(x))
            ]])
        end)

        it("protect record metatables", function()
            run_test([[
                local x = test.make_prim(123)
                assert(getmetatable(x) == false)
            ]])
        end)

        it("check record tags", function()
            -- TODO: change this message to mention the relevant record types
            -- instead of only saying "userdata"
            run_test([[
                local prim = test.make_prim(123)
                local ok, err = pcall(test.get_x, prim)
                assert(not ok)
                assert(string.find(err, "expected userdata but found userdata",
                        nil, true))
            ]])
        end)
    end)

    describe("I/O", function()
        setup(compile([[
            export function write(s:string)
                io.write(s)
            end
        ]]))

        it("io.write works", function()
            run_test([[
                test.write("Hello:)World")
            ]])
            assert_test_output("Hello:)World")
        end)
    end)

    describe("tofloat builtin", function()
        setup(compile([[
            export function itof(x:integer): float
                return tofloat(x)
            end
        ]]))

        it("works", function()
            run_test([[
                local x_i = 1
                local x_f = test.itof(x_i)
                assert("float" == math.type(x_f))
                assert(1.0 == x_f)
            ]])
        end)
    end)

    describe("math.sqrt builtin", function()
        setup(compile([[
            export function square_root(x: float): float
                return math.sqrt(x)
            end
        ]]))

        it("works on positive numbers", function()
            run_test([[
                assert(1.0 == test.square_root(1.0))
                assert(2.0 == test.square_root(4.0))
                assert(3.0 == test.square_root(9.0))
                assert(4.0 == test.square_root(16.0))
                assert(math.huge == test.square_root(math.huge))
            ]])
        end)

        it("returns NaN on negative numbers", function()
            run_test([[
                local x = test.square_root(-4.0)
                assert(x ~= x)
            ]])
        end)

        it("returns NaN on NaN", function()
            run_test([[
                local x = test.square_root(0.0 / 0.0)
                assert(x ~= x)
            ]])
        end)
    end)

    describe("string.char builtin", function()
        setup(compile([[
            export function chr(x: integer): string
                return string_.char(x)
            end
        ]]))

        it("works on normal characters", function()
            run_test([[
                for i = 1, 255 do
                    assert(string.char(i) == test.chr(i))
                end
            ]])
        end)

        it("works on zero", function()
            run_test([[
                assert(string.char(0) == test.chr(0))
            ]])
        end)

        it("error case", function()
            run_test([[
                local ok, err = pcall(test.chr, -1)
                assert(not ok)
                assert(string.find(err, "out of range", nil, true))

                local ok, err = pcall(test.chr, 256)
                assert(not ok)
                assert(string.find(err, "out of range", nil, true))
            ]])
        end)
    end)

    describe("string.sub builtin", function()
        setup(compile([[
            export function sub(s: string, i: integer, j: integer): string
                return string_.sub(s, i, j)
            end
        ]]))

        it("work", function()
            run_test([[
                local s = "abcde"
                for i = -10, 10 do
                    for j = -10, 10 do
                        assert(string.sub(s, i, j) == test.sub(s, i, j))
                    end
                end
            ]])
        end)
    end)

    describe("any", function()
        setup(compile([[
            export function id(x:any): any
                return x
            end

            export function call(f:any->any, x:any): any
                return f(x)
            end

            export function read(xs:{any}, i:integer): any
                return xs[i]
            end

            export function write(xs:{any}, i:integer, x:any): ()
                xs[i] = x
            end

            export function if_any(x:any): boolean
                if x then
                    return true
                else
                    return false
                end
            end

            export function while_any(x:any): integer
                local out = 0
                while x do
                    out = out + 1
                    x = false
                end
                return out
            end

            export function repeat_any(x:any): integer
                local out = 0
                repeat
                    out = out + 1
                    if out == 2 then
                        break
                    end
                until x
                return out
            end
        ]]))

        --
        -- All of these have a separate branch for the "any" and the non-"any"
        -- case. So we better stress them by testing the "any" case...
        --

        it("can receive and return anys", function()
            run_test([[ assert(17 == test.id(17)) ]])
            run_test([[ assert(true == test.id(true)) ]])
            run_test([[ assert(true == test.call(test.id, true)) ]])
        end)

        it("can read from array of any", function()
            run_test([[
                local xs = {10, "hello"}
                assert(10 == test.read(xs, 1))
                assert("hello" == test.read(xs, 2))
            ]])
        end)

        it("can write to array of any", function()
            run_test([[
                local xs = {}
                test.write(xs, 1, 10)
                test.write(xs, 2, "hello")
                assert(10 == xs[1])
                assert("hello" == xs[2])
            ]])
        end)

        it("can use any in if-statement condition", function()
            run_test([[
                assert(true == test.if_any(0))
                assert(true == test.if_any(true))
                assert(false == test.if_any(false))
                assert(false == test.if_any(nil))
            ]])
        end)

        it("can use any in while-statement condition", function()
            run_test([[
                assert(1 == test.while_any(0))
                assert(1 == test.while_any(true))
                assert(0 == test.while_any(false))
                assert(0 == test.while_any(nil))
            ]])
        end)

        it("can use any in repeat-until-statement condition", function()
            run_test([[
                assert(1 == test.repeat_any(0))
                assert(1 == test.repeat_any(true))
                assert(2 == test.repeat_any(false))
                assert(2 == test.repeat_any(nil))
            ]])
        end)
    end)

    describe("Corner cases of scoping", function()

        setup(compile([[
            record Point
                x: integer
                y: integer
            end

            local x = 10

            typealias y = integer

            ------

            local a, a = 5, 3

            ------

            export function f(): integer
                return 19
            end

            local function f(): integer
                return 53
            end

            ------

            export function g(): integer
                return 83
            end

            local g : string = 'preets'

            ------

            export h : string = 'madyanam'

            local function h(): integer
                return 1216
            end

            ------

            export i : string = 'baby'

            local i : string = 'yoda'

            ------

            export function toplevel_local_f(): integer
                return f()
            end

            export function toplevel_local_g_type(): string
                return type(g)
            end

            export function toplevel_local_h_type(): string
                return type(h)
            end

            export function toplevel_local_i(): string
                return i
            end

            export function toplevel_local_a(): integer
                return a
            end

            export function local_type(): integer
                local Point: Point = { x=1, y=2 }
                return Point.x
            end

            export function local_initializer(): integer
                local x = x + 1
                return x
            end

            export function for_type_annotation(): integer
                local res = 0
                for y:y = 1, 10 do
                    res = res + y
                end
                return res
            end

            export function for_initializer(): integer
                local res = 0
                for x = x + 1, x + 100, x-7 do
                    res = res + 1
                end
                return res
            end

            export function tofloat_shadowing(x:integer) : float
                local tofloat = 1.0
                return (x + tofloat)
            end

            export function duplicate_parameter(x: integer, x:integer) : integer
                return x
            end
        ]]))

        it("exported functions that are locally shadowed should be visible ouside the module", function ()
            run_test([[ assert('function' == type(test.g)) ]])
            run_test([[ assert(19 == test.f()) ]])
        end)

        it("exported variables that are locally shadowed should be visible outside the module", function ()
            run_test([[ assert('baby' == test.i) ]])
            run_test([[ assert('string' == type(test.h)) ]])
        end)

        it("local top-level variable shadows toplevel exported variable", function ()
            run_test([[ assert('yoda' == test.toplevel_local_i()) ]])
        end)

        it("local top-level function shadows toplevel exported variable", function ()
            run_test([[ assert('function' == test.toplevel_local_h_type()) ]])
        end)

        it("local top-level variable shadows toplevel exported function", function ()
            run_test([[ assert('string' == test.toplevel_local_g_type()) ]])
        end)

        it("local top-level function shadows toplevel exported function", function ()
            run_test([[ assert(53 == test.toplevel_local_f()) ]])
        end)

        it("local top-level variable is shadowed by the latest declaration", function ()
            run_test([[ assert(3 == test.toplevel_local_a()) ]])
        end)

        it("local variable doesn't shadow its type annotation", function()
            run_test([[ assert( 1 == test.local_type() ) ]])
        end)

        it("local variable scope doesn't shadow its initializer", function()
            run_test([[ assert( 11 == test.local_initializer() ) ]])
        end)

        it("for loop variable scope doesn't shadow its type annotation", function()
            run_test([[ assert( 55 == test.for_type_annotation() ) ]])
        end)

        it("for loop variable scope doesn't shadow its initializers", function()
            run_test([[ assert( 34 == test.for_initializer() ) ]])
        end)

        it("tofloat in coercions doesn't get shadowed", function()
            run_test([[ assert( 21.0 == test.tofloat_shadowing(20) ) ]])
        end)

        it("allows functions with repeated argument names", function()
            run_test([[ assert( 20 == test.duplicate_parameter(10, 20) )]])
        end)
    end)

    describe("Non-constant toplevel initializers", function()
        setup(compile([[
            export function f(): integer
                return 10
            end

            local x1 = f()
            local x2 = x1
            local x3 = -x2
            local x4: {integer} = { x1 }
            local x5: {x: integer} = { x = x1 }

            export function get_x1(): integer
                return x1
            end

            export function get_x2(): integer
                return x2
            end

            export function get_x3(): integer
                return x3
            end

            export function get_x4(): {integer}
                return x4
            end

            export function get_x5(): {x: integer}
                return x5
            end
        ]]))

        it("", function()
            run_test([[
                assert(  10 == test.get_x1() )
                assert(  10 == test.get_x2() )
                assert( -10 == test.get_x3() )
                local x4 = test.get_x4()
                assert( 1 == #x4 )
                assert( 10 == x4[1] )
                local x5 = test.get_x5()
                assert(10 == x5.x)
            ]])
        end)
    end)

    describe("Nested for loops", function()
        setup(compile([[
            export function mul(n: integer, m:integer) : integer
                local ret = 0
                for i = 1, n do
                    for j = 1, m do
                        ret = ret + 1
                    end
                end
                return ret
            end
        ]]))

        it("", function()
            run_test([[
                assert( 0 == test.mul(0, 2))
                assert( 0 == test.mul(2, 0))
                assert(15 == test.mul(3, 5))
            ]])
        end)
    end)

    describe("Constant propagation", function()
        setup(compile([[
            local x = 0 -- never read from
            local step = 1
            local counter = 0

            local function inc(): integer
                counter = counter + step
                return counter
            end

            export function next(): integer
                x = inc()
                return counter
            end
        ]]))

        it("preserves assignment side-effects", function()
            run_test([[
                assert(1 == test.next())
                assert(2 == test.next())
                assert(3 == test.next())
            ]])
        end)
    end)

    describe("Uninitialized variables", function()
        setup(compile([[
            export function sign(x: integer): integer
                local ret: integer
                if     x  < 0 then
                    ret = -1
                elseif x == 0 then
                    ret = 0
                else
                    ret = 1
                end
                return ret
            end

            export function non_breaking_loop(): integer
                local i = 1
                while true do
                    if i == 42 then return i end
                    i = i + 1
                end
            end

            export function initialize_inside_loop(): integer
                local x: integer
                repeat
                    x = 17
                until true
                return x
            end
        ]]))

        it("can be used", function()
            run_test([[
                assert(-1 == test.sign(-10))
                assert( 0 == test.sign(0))
                assert( 1 == test.sign(10))
            ]])
        end)

        it("infinite loops don't fall through", function()
            run_test([[
                assert(42 == test.non_breaking_loop())
            ]])
        end)

        it("can initialize inside loops", function()
            run_test([[
                assert(17 == test.initialize_inside_loop())
            ]])
        end)
    end)

    describe("For loop integer overflow", function()
        setup(compile([[
            export function loop(A: integer, B: integer, C: integer): {integer}
                local xs: {integer} = {}
                for i = A, B, C do
                    xs[#xs+1] = i
                end
                return xs
            end
        ]]))

        it("int loop avoids overflow", function()
            run_test([[
                local high = math.maxinteger
                local xs = test.loop(high-5, high, 10)
                assert(#xs == 1)
                assert(xs[1] == high-5)
            ]])
        end)

        it("int loop avoids underderflow", function()
            run_test([[
                local low = math.mininteger
                local xs = test.loop(low+5, low, -10)
                assert(#xs == 1)
                assert(xs[1] == low+5)
            ]])
        end)

        it("very large interval (up)", function()
            run_test([[
                local low  = math.mininteger
                local high = math.maxinteger
                local xs = test.loop(low, high, high)
                assert(#xs == 3)
                assert(xs[1] == low)
                assert(xs[2] == -1)
                assert(xs[3] == high-1)
            ]])
        end)

        it("very large interval (down)", function()
            run_test([[
                local low  = math.mininteger
                local high = math.maxinteger
                local xs = test.loop(high, low, low)
                assert(#xs == 2)
                assert(xs[1] == high)
                assert(xs[2] == -1)
            ]])
        end)
    end)

    describe("Multiple assignment", function()
        setup(compile([[
            typealias TPoint = {x:integer, y:integer}

            record RPoint
                x: integer
                y: integer
            end

            export function new_rpoint(x:integer, y:integer): RPoint
                return {x = x, y = y}
            end

            export function get_rpoint_fields(p:RPoint): (integer, integer)
                return p.x, p.y
            end

            local gi, ga: {integer} = 1, {}
            export function assign_global(): (integer, {integer})
                gi, ga[gi] = gi+1, 20
                return gi, ga
            end

            export function assign_local(): (integer, {integer})
                local li: integer = 1
                local la: {integer} = {}

                li, la[li] = li+1, 20
                return li, la
            end

            export function assign_bracket(): (integer, integer)
                local a: {integer} = {10, 20}

                a[1], a[2] = a[2], a[1]
                return a[1], a[2]
            end

            export function swap(): (integer, integer)
                local x, y = 10, 20
                x, y = y, x
                return x, y
            end

            export function swap_point(): TPoint
                local p:TPoint = { x = 10, y = 20 }
                p.x, p.y = p.y, p.x
                return p
            end

            export function assign_tables_1(a:{integer}, b:{integer}, c:integer): ({integer}, {integer})
                a, a[1] = b, c
                return a, b
            end

            export function assign_tables_2(a:{integer}, b:{integer}, c:integer): ({integer}, {integer})
                a[1], a = c, b
                return a, b
            end

            export function assign_dots_1(a:TPoint, b:TPoint, c:integer, d:integer): (TPoint, TPoint)
                a, a.x, a.y = b, c, d
                return a, b
            end

            export function assign_dots_2(a:TPoint, b:TPoint, c:integer, d:integer): (TPoint, TPoint)
                a.x, a.y, a = c, d, b
                return a, b
            end

            export function assign_recs_1(a:RPoint, b:RPoint, c:integer, d:integer): (RPoint, RPoint)
                a, a.x, a.y = b, c, d
                return a, b
            end

            export function assign_recs_2(a:RPoint, b:RPoint, c:integer, d:integer): (RPoint, RPoint)
                a.x, a.y, a = c, d, b
                return a, b
            end

            export function assign_same_var(): integer
                local a:integer
                a, a, a = 10, 20, 30
                return a
            end
        ]]))

        it("preserves evaluation order with local variables", function()
            run_test([[
                local i, ai = test.assign_local()
                assert(2   == i)
                assert(20  == ai[1])
                assert(nil == ai[2])
            ]])
        end)

        it("preserves evaluation order with global variables", function()
            run_test([[
                local i, ai = test.assign_global()
                assert(2   == i)
                assert(20  == ai[1])
                assert(nil == ai[2])
            ]])
        end)

        it("preserves evaluation order with bracket variables", function()
            run_test([[
                local i, j = test.assign_bracket()
                assert(20 == i)
                assert(10 == j)
            ]])
        end)

        it("preserves evaluation order with dot variables", function()
            run_test([[
                local p = test.swap_point()
                assert(20 == p.x)
                assert(10 == p.y)
            ]])
        end)

        it("swap variables correctly", function()
            run_test([[
                local x, y = test.swap()
                assert(20 == x)
                assert(10 == y)
            ]])
        end)

        it("use temporary variables correctly on arrays assignments 1", function()
            run_test([[
                local a, b = {10}, {20}
                local t = table.pack(test.assign_tables_1(a, b, 30))
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(30 == a[1])
                assert(20 == b[1])
            ]])
        end)

        it("use temporary variables correctly on arrays assignments 2", function()
            run_test([[
                local a, b = {10}, {20}
                local t = table.pack(test.assign_tables_2(a, b, 30))
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(30 == a[1])
                assert(20 == b[1])
            ]])
        end)

        it("use temporary variables correctly on tables assignments 1", function()
            run_test([[
                local a, b = {x = 10, y = 20}, {x = 30, y = 40}
                local t = table.pack(test.assign_dots_1(a, b, 50, 60))
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(50 == a.x)
                assert(60 == a.y)
                assert(30 == b.x)
                assert(40 == b.y)
            ]])
        end)

        it("use temporary variables correctly on tables assignments 2", function()
            run_test([[
                local a, b = {x = 10, y = 20}, {x = 30, y = 40}
                local t = table.pack(test.assign_dots_2(a, b, 50, 60))
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(50 == a.x)
                assert(60 == a.y)
                assert(30 == b.x)
                assert(40 == b.y)
            ]])
        end)

        it("use temporary variables correctly on records assignments 1", function()
            run_test([[
                local a, b = test.new_rpoint(10, 20), test.new_rpoint(30, 40)
                local t = table.pack(test.assign_recs_1(a, b, 50, 60))
                local ax, ay = test.get_rpoint_fields(a)
                local bx, by = test.get_rpoint_fields(b)
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(50 == ax)
                assert(60 == ay)
                assert(30 == bx)
                assert(40 == by)
            ]])
        end)

        it("use temporary variables correctly on records assignments 2", function()
            run_test([[
                local a, b = test.new_rpoint(10, 20), test.new_rpoint(30, 40)
                local t = table.pack(test.assign_recs_2(a, b, 50, 60))
                local ax, ay = test.get_rpoint_fields(a)
                local bx, by = test.get_rpoint_fields(b)
                assert(2  == t.n)
                assert(b  == t[1])
                assert(b  == t[2])
                assert(50 == ax)
                assert(60 == ay)
                assert(30 == bx)
                assert(40 == by)
            ]])
        end)

        it("multiple assignment to same variable works correctly", function()
            run_test([[
                local a = test.assign_same_var()
                assert(10 == a)
            ]])
        end)
    end)

    describe("Multiple returns", function()
        setup(compile([[
            export function f(): (integer, integer, integer)
                return 10, 20, 30
            end

            export function g(x:integer, y:integer, z:integer): integer
                return x + y + z
            end

            export function func_as_param(): integer
                local a = g(f())
                return a
            end

            export function func_as_return(): (integer, integer, integer)
                return f()
            end

            export function func_as_first_return(): (integer, integer)
                return f(), 42
            end

            export function func_as_only_exp(): integer
                local a, b, c = f()
                return a + b + c
            end

            export function func_inside_paren(): integer
                return (f())
            end

            export function assign_same_var_1(): integer
                local x: integer
                x, x, x = f()
                return x
            end

            export function assign_same_var_2(): integer
                local x: integer
                local y: integer
                x, y, y = f()
                return y
            end
        ]]))

        it("works as function arguments", function()
            run_test([[
                local a = test.func_as_param()
                assert(60 == a)
            ]])
        end)

        it("works as only return value on multiple return", function()
            run_test([[
                local t = table.pack(test.func_as_return())
                assert(3  == t.n)
                assert(10 == t[1])
                assert(20 == t[2])
                assert(30 == t[3])
            ]])
        end)

        it("works as first return value on multiple return", function()
            run_test([[
                local t = table.pack(test.func_as_first_return())
                assert(2  == t.n)
                assert(10 == t[1])
                assert(42 == t[2])
            ]])
        end)

        it("works as only expression on a declaration", function()
            run_test([[
                local a = test.func_as_only_exp()
                assert(60 == a)
            ]])
        end)

        it("works inside parenthesis", function()
            run_test([[
                local t = table.pack(test.func_inside_paren())
                assert(1  == t.n)
                assert(10 == t[1])
            ]])
        end)

        it("assigns return values from right to left (1)", function()
            run_test([[
                local x = test.assign_same_var_1()
                assert(x == 10)
            ]])
        end)

        it("assigns return values from right to left (2)", function()
            run_test([[
                local y = test.assign_same_var_2()
                assert(y == 20)
            ]])
        end)
    end)

end)
