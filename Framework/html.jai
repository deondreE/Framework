#import "String";

HTMLTokenType :: enum {
    OPENTag;
    CLOSETag;
    TEXT;
    EOF;
}

HTMLToken :: struct {
    type: HTMLTokenType;
    name: string;
    data: string;
}

HTMLParser :: struct {
    input: string;
    cursor: int;
}

get_next_token :: (parser: *HTMLParser) -> HTMLToken {
    token: HTMLToken;

    if parser.cursor >= parser.input.count {
        token.type = .EOF;
        return token;
    }

    remaining := advance(parser.input, parser.cursor);

    if remaining[0] == #char "<" {
        // Find the end of tag
        end_index  := find_index_from_left(remaining, ">");
        if end_index == -1 {
            parser.cursor = parser.input.count;
            token.type = .EOF;
            return token;
        }

        tag_content := slice(remaining, 1, end_index - 1);
        parser.cursor += end_index + 1;

        if tag_content[0] == #char "/" {
            token.type = .CLOSETag;
            token.name = slice(tag_content, 1, tag_content.count - 1);
        } else {
            token.type = .OPENTag;
            space_index := find_index_from_left(tag_content, " ");
            if space_index != -1 {
                token.name = slice(tag_content, 0, space_index);
            } else {
                token.name = tag_content;
            }
        }
    } else {
        next_tag := find_index_from_left(remaining, "<");
        if next_tag == -1 {
            token.data = remaining;
            parser.cursor = parser.input.count;
        } else {
            token.data = slice(remaining, 0, next_tag);
            parser.cursor += next_tag;
        }
        token.type = .TEXT;
    }

    return token;
}

render_html :: (layout: *Layout, html_string: string, window_width: float32, window_height: float32) 
{
    parser: HTMLParser;
    parser.input = html_string;

    while true {
        token := get_next_token(*parser);
        if token.type == {
            case .EOF;
            break;
            case .TEXT;
            text := trim(token.data);
            if text.count == 0 continue;

            r := layout_reserve_space(layout, 0, 25);
            draw_text(text, r.x, r.y, window_width, window_height, 1.0, 300);
            case .OPENTag;
            if token.name == {
                case "h1";
                    // Font scale
                case "div";
                    // Child layout maybe
                case "hr";
                    r := layout_reserve_space(layout, 0, 2);
                    draw_rect(r.x, r.y, r.w, r.h, .[0.5,0.5,0.5,1.0]);
            }
        }
    }
}