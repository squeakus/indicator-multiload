/******************************************************************************
 * Copyright (C) 2011  Michael Hofmann <mh21@piware.de>                       *
 *                                                                            *
 * This program is free software; you can redistribute it and/or modify       *
 * it under the terms of the GNU General Public License as published by       *
 * the Free Software Foundation; either version 3 of the License, or          *
 * (at your option) any later version.                                        *
 *                                                                            *
 * This program is distributed in the hope that it will be useful,            *
 * but WITHOUT ANY WARRANTY; without even the implied warranty of             *
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the              *
 * GNU General Public License for more details.                               *
 *                                                                            *
 * You should have received a copy of the GNU General Public License along    *
 * with this program; if not, write to the Free Software Foundation, Inc.,    *
 * 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.                *
 ******************************************************************************/

Quark expression_error_quark() {
  return Quark.from_string("expression-error-quark");
}

public class ExpressionParser {
    Data[] datas;

    public ExpressionParser(Data[] datas) {
        this.datas = datas;
    }

    private static void expandtoken(char *current,
            ref char *last) {
        if (last == null)
            last = current;
        // stderr.printf("Expanding token to '%s'\n", strndup(last, current - last + 1));
    }

    private static string[] savetoken(char *current,
            ref char *last, string[] result) {
        string[] r = result;
        if (last != null) {
            var token = strndup(last, current - last);
            // stderr.printf("Saving token '%s'\n", token);
            r += token;
            last = null;
        } else {
            // stderr.printf("Not saving empty token\n");
        }
        return r;
    }

    private static string[] addtoken(char current,
            string[] result) {
        string[] r = result;
        var token = current.to_string();
        // stderr.printf("Adding token '%s'\n", token);
        r += token;
        return r;
    }

    private static bool isspace(char current) {
        return current == ' ';
    }

    private static bool isvariable(char current) {
        return
            current >= 'a' && current <= 'z' ||
            current >= '0' && current <= '9' ||
            current == '.';
    }

    public string[] tokenize(string expression) {
        string[] result = null;
        char *last = null;
        char *current = expression;
        int level = 0;
        bool inexpression = false;
        for (; *current != '\0'; current = current + 1) {
            if (!inexpression) {
                if (*current == '$') {
                    result = savetoken(current, ref last, result);
                    result = addtoken(*current, result);
                    inexpression = true;
                } else {
                    expandtoken(current, ref last);
                }
            } else {
                if (level == 0) {
                    if (isvariable(*current)) {
                        expandtoken(current, ref last);
                    } else if (last == null && *current == '(') {
                        result = addtoken(*current, result);
                        ++level;
                    } else {
                        result = addtoken('(', result);
                        result = savetoken(current, ref last, result);
                        result = addtoken(')', result);
                        expandtoken(current, ref last);
                        inexpression = false;
                    }
                } else {
                    if (*current == '(') {
                        result = savetoken(current, ref last, result);
                        result = addtoken(*current, result);
                        ++level;
                    } else if (*current == ')') {
                        result = savetoken(current, ref last, result);
                        result = addtoken(*current, result);
                        --level;
                        if (level == 0)
                            inexpression = false;
                    } else if (isspace(*current)) {
                        result = savetoken(current, ref last, result);
                    } else if (!isvariable(*current)) {
                        result = savetoken(current, ref last, result);
                        result = addtoken(*current, result);
                    } else {
                        expandtoken(current, ref last);
                    }
                }
            }
        }
        result = savetoken(current, ref last, result);

        return result;
    }

    private Error error(uint index, string message) {
        return new Error(expression_error_quark(), (int)index, "%s", message);
    }

    private string evaluate_expression(string[] tokens, ref uint index) throws Error {
        if (index >= tokens.length)
            throw error(index, "empty expression");
        if (tokens[index] == "(")
            return evaluate_expression_parens(tokens, ref index);
        return evaluate_expression_identifier(tokens, ref index);
    }

    private string evaluate_expression_times(string[] tokens, ref uint index) throws Error {
        string result = null;
        bool div = false;
        for (;;) {
            if (index >= tokens.length)
                throw error(index, "expression expected");
            var value = evaluate_expression(tokens, ref index);
            if (result == null)
                result = value;
            else if (!div)
                result = (double.parse(result) * double.parse(value)).to_string();
            else
                result = (double.parse(result) / double.parse(value)).to_string();
            if (index >= tokens.length)
                return result;
            switch (tokens[index]) {
            case "*":
                div = false;
                ++index;
                continue;
            case "/":
                div = true;
                ++index;
                continue;
            default:
                return result;
            }
        }
    }

    private string evaluate_expression_plus(string[] tokens, ref uint index) throws Error {
        string result = null;
        bool minus = false;
        for (;;) {
            if (index >= tokens.length)
                throw error(index, "expression expected");
            var value = evaluate_expression_times(tokens, ref index);
            if (result == null)
                result = value;
            else if (!minus)
                result = (double.parse(result) + double.parse(value)).to_string();
            else
                result = (double.parse(result) - double.parse(value)).to_string();
            if (index >= tokens.length)
                return result;
            switch (tokens[index]) {
            case "+":
                minus = false;
                ++index;
                continue;
            case "-":
                minus = true;
                ++index;
                continue;
            default:
                return result;
            }
        }
    }

    private string evaluate_expression_parens(string[] tokens, ref uint index) throws Error {
        if (index >= tokens.length || tokens[index] != "(")
            throw error(index, "'(' expected");
        ++index;
        var result = evaluate_expression_plus(tokens, ref index);
        if (index >= tokens.length || tokens[index] != ")")
            throw error(index, "')' expected");
        ++index;
        return result;
    }

    private string[] evaluate_expression_params(string[] tokens, ref uint index) throws Error {
        string[] result = null;
        if (index >= tokens.length || tokens[index] != "(")
            throw error(index, "'(' expected");
        ++index;
        if (index >= tokens.length)
            throw error(index, "parameters expected");
        if (tokens[index] != ")") {
            for (;;) {
                result += evaluate_expression_plus(tokens, ref index);
                if (index >= tokens.length)
                    throw error(index, "')' expected");
                if (tokens[index] != ",")
                    break;
                ++index;
            }
        }
        if (index >= tokens.length || tokens[index] != ")")
            throw error(index, "')' expected");
        ++index;
        return result;
    }

    private string evaluate_expression_identifier(string[] tokens, ref uint index) throws Error {
        if (index >= tokens.length)
            throw error(index, "identifier expected");
        double sign = 1;
        if (tokens[index] == "+") {
            ++index;
            if (index >= tokens.length)
                throw error(index, "identifier expected");
        } else if (tokens[index] == "-") {
            sign = -1.0;
            ++index;
            if (index >= tokens.length)
                throw error(index, "identifier expected");
        }
        var token = tokens[index];
        if (token.length > 0 && (token[0] >= '0' && token[0] <= '9' || token[0] == '.')) {
            ++index;
            if (sign == -1)
                return "-" + token;
            return token;
        }
        var varparts = token.split(".");
        var nameindex = index;
        ++index;
        switch (varparts.length) {
        case 1:
            var function = varparts[0];
            var parameters = evaluate_expression_params(tokens, ref index);
            switch (function) {
            case "decimals":
                if (parameters.length < 2)
                    throw error(index, "at least two parameters expected");
                return "%.*f".printf(int.parse(parameters[1]), sign * double.parse(parameters[0]));
            case "size":
                if (parameters.length < 1)
                    throw error(index, "at least one parameter expected");
                return Utils.format_size(sign * double.parse(parameters[0]));
            case "speed":
                if (parameters.length < 1)
                    throw error(index, "at least one parameter expected");
                return Utils.format_speed(sign * double.parse(parameters[0]));
            case "percent":
                if (parameters.length < 1)
                    throw error(index, "at least one parameter expected");
                return _("%u%%").printf
                    ((uint)Math.round(100 * sign * double.parse(parameters[0])));
            default:
                throw error(nameindex, "unknown function");
            }
        case 2:
            foreach (var data in this.datas) {
                if (data.id != varparts[0])
                    continue;
                for (uint j = 0, jsize = data.keys.length; j < jsize; ++j) {
                    if (data.keys[j] != varparts[1])
                        continue;
                    return (sign * data.values[j]).to_string();
                }
            }
            throw error(nameindex, "unknown variable");
        default:
            throw error(nameindex, "too many identifier parts");
        }
    }

    private string evaluate_text(string[] tokens, ref uint index) throws Error {
        string[] result = null;
        while (index < tokens.length) {
            string current = tokens[index];
            if (current == "$") {
                ++index;
                result += evaluate_expression(tokens, ref index);
            } else {
                result += current;
                ++index;
            }
        }

        return string.joinv("", result);
    }

    public string evaluate(string[] tokens) {
        uint index = 0;
        try {
            return evaluate_text(tokens, ref index);
        } catch (Error e) {
            stderr.printf("Expression error: %s\n", e.message);
            string errormessage = "";
            int errorpos = -1;
            for (uint i = 0, isize = tokens.length; i < isize; ++i) {
                if (e.code == i)
                    errorpos = errormessage.length;
                errormessage += " " + tokens[i];
            }
            if (errorpos < 0)
                errorpos = errormessage.length;
            stderr.printf("%s\n%s^\n", errormessage, string.nfill(errorpos, '-'));
            return "";
        }
    }
}
