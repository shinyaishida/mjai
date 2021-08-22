window.Dytem = {
  init() {
    return Dytem.addChildrenField($('body'), null, Dytem);
  },
  assign(obj, elem) {
    elem || (elem = Dytem);
    if (typeof obj === 'string') {
      return elem.text(obj);
    }
    if (obj instanceof Array) {
      elem.clear();
      const results = [];
      for (let i = 0; i < obj.length; i += 1) {
        results.push(Dytem.assign(obj[i], elem.append()));
      }
      return results;
    }
    const results2 = [];
    Object.keys(obj).forEach((name) => {
      if (name === 'text') {
        results2.push(elem.text(obj[name]));
      } else if (name === 'html') {
        results2.push(elem.html(obj[name]));
      } else if (elem[name]) {
        results2.push(Dytem.assign(obj[name], elem[name]));
      } else if (elem.attr) {
        results2.push(elem.attr(name, obj[name]));
      } else {
        throw Error(`unknown field: ${name}`);
      }
    });
    return results2;
  },
  addChildrenField(elem, prefix, target) {
    return elem.find('[id]').each((i, child) => {
      const childId = $(child).attr('id');
      if (prefix) $(child).removeAttr('id');
      const escPrefix = prefix ? prefix.replace(/\./, '\\.') : '';
      if (childId.match(new RegExp(`^${escPrefix}([^\\.]+)$`))) {
        const name = RegExp.$1;
        target[name] = ($(child).hasClass('repeated'))
          ? new Repeated(childId, $(child))
          : $(child);
        return target[name];
      }
    });
  },
};

let Repeated = (function () {
  function Repeated(id, placeholder) {
    this.id = id;
    this.placeholder = placeholder;
    this.template = $(document.getElementById(this.id));
    this.elements = [];
  }

  Repeated.prototype.append = function () {
    const lastElem = (this.elements.length > 0)
      ? this.elements[this.elements.length - 1]
      : this.placeholder;
    const newElem = this.template.clone();
    newElem.removeAttr('id');
    Dytem.addChildrenField(newElem, `${this.id}.`, newElem);
    newElem.show();
    lastElem.after(newElem);
    this.elements.push(newElem);
    return newElem;
  };

  Repeated.prototype.at = function (idx) {
    return this.elements[idx];
  };

  Repeated.prototype.size = function () {
    return this.elements.length;
  };

  Repeated.prototype.resize = function (n) {
    if (n < this.elements.length) {
      const ref = this.elements.slice(n);
      for (let i = 0; i < ref.length; i += 1) {
        ref[i].remove();
      }
      return ([].splice.apply(this.elements, [n, 9e9].concat([])), []);
    } if (n > this.elements.length) {
      const results = [];
      const ref3 = this.elements.length;
      for (let i = ref3; ref3 <= n ? i < n : i > n; i += ref3 <= n ? 1 : -1) {
        results.push(this.append());
      }
      return results;
    }
  };

  Repeated.prototype.clear = function () {
    for (let i = 0; i < this.elements.length; i += 1) {
      this.elements[i].remove();
    }
    this.elements = [];
    return this.elements;
  };

  return Repeated;
}());
