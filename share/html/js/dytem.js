let Repeated;

window.Dytem = {
  init() {
    return Dytem.addChildrenField($('body'), null, Dytem);
  },
  assign(obj, elem) {
    let childElem; let childObj; let name; let _i; let _len; let _results; let
      _results2;
    elem || (elem = Dytem);
    if (typeof obj === 'string') {
      return elem.text(obj);
    } if (obj instanceof Array) {
      elem.clear();
      _results = [];
      for (_i = 0, _len = obj.length; _i < _len; _i++) {
        childObj = obj[_i];
        childElem = elem.append();
        _results.push(Dytem.assign(childObj, childElem));
      }
      return _results;
    }
    _results2 = [];
    for (name in obj) {
      childObj = obj[name];
      if (name === 'text') {
        _results2.push(elem.text(childObj));
      } else if (name === 'html') {
        _results2.push(elem.html(childObj));
      } else if (elem[name]) {
        _results2.push(Dytem.assign(childObj, elem[name]));
      } else if (elem.attr) {
        _results2.push(elem.attr(name, childObj));
      } else {
        throw `unknown field: ${name}`;
      }
    }
    return _results2;
  },
  addChildrenField(elem, prefix, target) {
    const _this = this;
    return elem.find('[id]').each((i, child) => {
      let childId; let escPrefix; let
        name;
      childId = $(child).attr('id');
      if (prefix) $(child).removeAttr('id');
      escPrefix = prefix ? prefix.replace(/\./, '\\.') : '';
      if (childId.match(new RegExp(`^${escPrefix}([^\\.]+)$`))) {
        name = RegExp.$1;
        if ($(child).hasClass('repeated')) {
          return target[name] = new Repeated(childId, $(child));
        }
        return target[name] = $(child);
      }
    });
  },
};

Repeated = (function () {
  function Repeated(__id, __placeholder) {
    this.__id = __id;
    this.__placeholder = __placeholder;
    this.__template = $(document.getElementById(this.__id));
    this.__elems = [];
  }

  Repeated.prototype.append = function () {
    let lastElem; let
      newElem;
    if (this.__elems.length > 0) {
      lastElem = this.__elems[this.__elems.length - 1];
    } else {
      lastElem = this.__placeholder;
    }
    newElem = this.__template.clone();
    newElem.removeAttr('id');
    Dytem.addChildrenField(newElem, `${this.__id}.`, newElem);
    newElem.show();
    lastElem.after(newElem);
    this.__elems.push(newElem);
    return newElem;
  };

  Repeated.prototype.at = function (idx) {
    return this.__elems[idx];
  };

  Repeated.prototype.size = function () {
    return this.__elems.length;
  };

  Repeated.prototype.resize = function (n) {
    let elem; let i; let _i; let _len; let _ref; let _ref2; let _ref3; let
      _results;
    if (n < this.__elems.length) {
      _ref = this.__elems.slice(n);
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        elem = _ref[_i];
        elem.remove();
      }
      return ([].splice.apply(this.__elems, [n, 9e9].concat(_ref2 = [])), _ref2);
    } if (n > this.__elems.length) {
      _results = [];
      for (i = _ref3 = this.__elems.length; _ref3 <= n ? i < n : i > n; _ref3 <= n ? i++ : i--) {
        _results.push(this.append());
      }
      return _results;
    }
  };

  Repeated.prototype.clear = function () {
    let elem; let _i; let _len; let
      _ref;
    _ref = this.__elems;
    for (_i = 0, _len = _ref.length; _i < _len; _i++) {
      elem = _ref[_i];
      elem.remove();
    }
    return this.__elems = [];
  };

  return Repeated;
}());
